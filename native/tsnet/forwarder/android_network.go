package tsnetforwarder

import (
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/netip"
	"slices"
	"strings"
	"sync"

	"tailscale.com/net/netmon"
)

// The Android runtime does not allow Go's net.Interfaces on recent SDKs. The
// Java side supplies the same information as JSON before tsnet is started.
type androidNetworkState struct {
	mu         sync.RWMutex
	ifaces     []netmon.Interface
	lastErr    error
	configured bool
}

var androidNetwork androidNetworkState

type androidInterfaceJSON struct {
	Name      string               `json:"name"`
	Index     int                  `json:"index"`
	MTU       int                  `json:"mtu"`
	Up        bool                 `json:"up"`
	Broadcast bool                 `json:"broadcast"`
	Loopback  bool                 `json:"loopback"`
	PointToPt bool                 `json:"pointToPoint"`
	Multicast bool                 `json:"multicast"`
	Addrs     []androidAddressJSON `json:"addrs"`
}

type androidAddressJSON struct {
	IP        string `json:"ip"`
	PrefixLen int    `json:"prefixLen"`
}

func androidInterfaces() ([]netmon.Interface, error) {
	androidNetwork.mu.RLock()
	defer androidNetwork.mu.RUnlock()
	if !androidNetwork.configured {
		return nil, nil
	}
	if androidNetwork.lastErr != nil {
		return nil, androidNetwork.lastErr
	}
	return cloneInterfaces(androidNetwork.ifaces), nil
}

// SetAndroidNetworkInterfaces installs an Android-provided interface snapshot.
// defaultIfName may be empty when Android has no active default network.
func (f *Forwarder) SetAndroidNetworkInterfaces(payload, defaultIfName string) (err error) {
	defer func() {
		if recovered := recover(); recovered != nil {
			err = fmt.Errorf("configure Android network interfaces: %v", recovered)
		}
	}()
	ifaces, err := parseAndroidInterfaces(payload)
	androidNetwork.mu.Lock()
	androidNetwork.configured = true
	androidNetwork.ifaces = ifaces
	androidNetwork.lastErr = err
	androidNetwork.mu.Unlock()
	if err != nil {
		return err
	}
	// Register only after a valid snapshot is available. An empty Android
	// snapshot is not a usable replacement for the standard interface query.
	netmon.RegisterInterfaceGetter(androidInterfaces)
	updateAndroidDefaultRouteInterface(strings.TrimSpace(defaultIfName))
	return nil
}

func parseAndroidInterfaces(payload string) ([]netmon.Interface, error) {
	if strings.TrimSpace(payload) == "" {
		return nil, errors.New("android network interface payload is empty")
	}
	var input []androidInterfaceJSON
	if err := json.Unmarshal([]byte(payload), &input); err != nil {
		return nil, err
	}
	output := make([]netmon.Interface, 0, len(input))
	for _, item := range input {
		if strings.TrimSpace(item.Name) == "" {
			continue
		}
		iface := netmon.Interface{
			Interface: &net.Interface{Name: item.Name, Index: item.Index, MTU: item.MTU},
			AltAddrs:  []net.Addr{},
		}
		if item.Up {
			iface.Flags |= net.FlagUp
		}
		if item.Broadcast {
			iface.Flags |= net.FlagBroadcast
		}
		if item.Loopback {
			iface.Flags |= net.FlagLoopback
		}
		if item.PointToPt {
			iface.Flags |= net.FlagPointToPoint
		}
		if item.Multicast {
			iface.Flags |= net.FlagMulticast
		}
		for _, address := range item.Addrs {
			addr, err := androidNetAddr(address)
			if err == nil {
				iface.AltAddrs = append(iface.AltAddrs, addr)
			}
		}
		output = append(output, iface)
	}
	return output, nil
}

func androidNetAddr(address androidAddressJSON) (net.Addr, error) {
	parsed, err := netip.ParseAddr(address.IP)
	if err != nil {
		return nil, err
	}
	zone := parsed.Zone()
	ip := net.IP(slices.Clone(parsed.AsSlice()))
	if zone != "" {
		return &net.IPAddr{IP: ip, Zone: zone}, nil
	}
	bits := 128
	if parsed.Is4() {
		bits = 32
	}
	if address.PrefixLen < 0 || address.PrefixLen > bits {
		return &net.IPAddr{IP: ip}, nil
	}
	return &net.IPNet{IP: ip, Mask: net.CIDRMask(address.PrefixLen, bits)}, nil
}

func cloneInterfaces(input []netmon.Interface) []netmon.Interface {
	output := make([]netmon.Interface, len(input))
	for i, iface := range input {
		output[i] = iface
		if iface.Interface != nil {
			copy := *iface.Interface
			output[i].Interface = &copy
		}
		output[i].AltAddrs = append([]net.Addr(nil), iface.AltAddrs...)
	}
	return output
}
