package tsnetforwarder

import (
	"os"
	"path/filepath"
	"testing"
)

func TestNewState(t *testing.T) {
	f := New()
	state := f.Status()
	if state.Phase != "new" {
		t.Fatalf("phase = %q, want new", state.Phase)
	}
	if state.ForwardCount != 0 {
		t.Fatalf("forward count = %d, want 0", state.ForwardCount)
	}
}

func TestConfigureRequiresAuthAndState(t *testing.T) {
	f := New()
	if err := f.Configure("", "android", t.TempDir()); err == nil {
		t.Fatal("Configure accepted an empty auth key")
	}
	if err := f.Configure("tskey-auth-test", "android", ""); err == nil {
		t.Fatal("Configure accepted an empty state directory")
	}
}

func TestConfigureAllowsExistingStateWithoutAuthKey(t *testing.T) {
	stateDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(stateDir, persistedLoginMarker), nil, 0o600); err != nil {
		t.Fatal(err)
	}
	f := New()
	if err := f.Configure("", "android", stateDir); err != nil {
		t.Fatalf("Configure() error = %v", err)
	}
}

func TestHasPersistedLogin(t *testing.T) {
	f := New()
	stateDir := t.TempDir()
	if f.HasPersistedLogin(stateDir) {
		t.Fatal("empty state directory reported a persisted login")
	}
	if err := os.WriteFile(filepath.Join(stateDir, persistedLoginMarker), nil, 0o600); err != nil {
		t.Fatal(err)
	}
	if !f.HasPersistedLogin(stateDir) {
		t.Fatal("persisted login marker was not detected")
	}
}

func TestConfigurePersistsNormalizedState(t *testing.T) {
	f := New()
	stateDir := filepath.Join(t.TempDir(), "nested", "tsnet")
	if err := f.Configure(" tskey-auth-test ", " android ", stateDir); err != nil {
		t.Fatalf("Configure() error = %v", err)
	}
	state := f.Status()
	if state.Phase != "configured" {
		t.Fatalf("phase = %q, want configured", state.Phase)
	}
	if state.Hostname != "android" {
		t.Fatalf("hostname = %q, want android", state.Hostname)
	}
	if f.stateDir != filepath.Clean(stateDir) {
		t.Fatalf("state dir = %q, want %q", f.stateDir, filepath.Clean(stateDir))
	}
}

func TestStartForwardValidation(t *testing.T) {
	f := New()
	cases := []struct {
		name       string
		host       string
		remotePort int
		localPort  int
	}{
		{name: "blank host", host: " ", remotePort: 5555},
		{name: "bad remote port", host: "100.64.0.1", remotePort: 0},
		{name: "bad local port", host: "100.64.0.1", remotePort: 5555, localPort: 65536},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := f.StartForward(tc.host, tc.remotePort, tc.localPort); err == nil {
				t.Fatal("StartForward accepted invalid input")
			}
		})
	}
}

func TestCloseIsIdempotent(t *testing.T) {
	f := New()
	f.Close()
	f.Close()
	if got := f.Status().Phase; got != "closed" {
		t.Fatalf("phase = %q, want closed", got)
	}
}

func TestSetAndroidNetworkInterfaces(t *testing.T) {
	f := New()
	payload := `[{"name":"wlan0","index":30,"mtu":1500,"up":true,"broadcast":true,"loopback":false,"pointToPoint":false,"multicast":true,"addrs":[{"ip":"192.168.31.65","prefixLen":24}]}]`
	if err := f.SetAndroidNetworkInterfaces(payload, "wlan0"); err != nil {
		t.Fatalf("SetAndroidNetworkInterfaces() error = %v", err)
	}
	ifaces, err := androidInterfaces()
	if err != nil {
		t.Fatalf("androidInterfaces() error = %v", err)
	}
	if len(ifaces) != 1 || ifaces[0].Name != "wlan0" {
		t.Fatalf("interfaces = %#v, want wlan0", ifaces)
	}
	if len(ifaces[0].AltAddrs) != 1 || ifaces[0].AltAddrs[0].String() != "192.168.31.65/24" {
		t.Fatalf("addresses = %#v, want 192.168.31.65/24", ifaces[0].AltAddrs)
	}
}

func TestSetAndroidNetworkInterfacesRejectsInvalidJSON(t *testing.T) {
	f := New()
	if err := f.SetAndroidNetworkInterfaces("not-json", ""); err == nil {
		t.Fatal("accepted invalid Android interface JSON")
	}
}
