// Package tsnetforwarder exposes an application-scoped TCP forwarder backed by
// Tailscale tsnet. It intentionally does not create a system VPN interface.
package tsnetforwarder

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/netip"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"

	"tailscale.com/tsnet"
)

const (
	defaultConnectTimeout = 60 * time.Second
	defaultDialTimeout    = 15 * time.Second
	// Keep the on-disk marker name stable so existing node identities can be reused.
	persistedLoginMarker = ".libtsnet-enrolled"
)

// State is a stable snapshot suitable for exposing to Android bindings.
type State struct {
	Phase          string
	Hostname       string
	LocalAddresses []string
	ForwardCount   int
	LastError      string
}

// Forward describes one loopback listener and its Tailscale destination.
type Forward struct {
	ID         string
	RemoteHost string
	RemotePort int
	LocalPort  int
}

type forward struct {
	Forward
	listener net.Listener
	cancel   context.CancelFunc
	done     chan struct{}
	workers  sync.WaitGroup
}

// Forwarder owns one tsnet server and zero or more loopback forwards.
type Forwarder struct {
	lifecycle     sync.Mutex
	mu            sync.RWMutex
	forwardMu     sync.RWMutex
	server        *tsnet.Server
	authKey       string
	hostname      string
	stateDir      string
	phase         string
	lastErr       string
	addresses     []string
	forwards      map[string]*forward
	connectCancel context.CancelFunc
	closing       int
}

// New returns an unconfigured forwarder.
func New() *Forwarder {
	return &Forwarder{
		phase:    "new",
		forwards: make(map[string]*forward),
	}
}

// Configure sets the tsnet credentials and persistent state directory.
// Configuration is rejected while the server is active.
func (f *Forwarder) Configure(authKey, hostname, stateDir string) error {
	f.lifecycle.Lock()
	defer f.lifecycle.Unlock()
	authKey = strings.TrimSpace(authKey)
	hostname = strings.TrimSpace(hostname)
	stateDir = strings.TrimSpace(stateDir)
	if !filepath.IsAbs(stateDir) || filepath.Dir(filepath.Clean(stateDir)) == filepath.Clean(stateDir) {
		return errors.New("an absolute application-private state directory is required")
	}
	stateDir = filepath.Clean(stateDir)
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.server != nil || f.closing > 0 {
		return errors.New("cannot configure an active or closing forwarder")
	}
	if err := os.MkdirAll(stateDir, 0o700); err != nil {
		return fmt.Errorf("create state directory: %w", err)
	}
	if authKey == "" {
		if _, err := os.Stat(filepath.Join(stateDir, persistedLoginMarker)); err != nil {
			if errors.Is(err, os.ErrNotExist) {
				return errors.New("auth key is required for first-time enrollment")
			}
			return fmt.Errorf("check existing tsnet state: %w", err)
		}
	}

	f.authKey = authKey
	f.hostname = hostname
	f.stateDir = stateDir
	if f.forwards == nil {
		f.forwards = make(map[string]*forward)
	}
	f.phase = "configured"
	f.lastErr = ""
	return nil
}

// Connect starts tsnet and waits for it to become usable.
func (f *Forwarder) Connect() (err error) {
	f.lifecycle.Lock()
	defer f.lifecycle.Unlock()
	var server *tsnet.Server
	var cancel context.CancelFunc
	defer func() {
		if recovered := recover(); recovered != nil {
			err = fmt.Errorf("connect tsnet panic: %v", recovered)
		}
		if cancel != nil {
			cancel()
		}
		f.mu.Lock()
		f.connectCancel = nil
		f.mu.Unlock()
		if err != nil {
			err = f.setError(err)
			if server != nil {
				_ = server.Close()
			}
		}
	}()
	f.mu.Lock()
	if f.closing > 0 {
		f.mu.Unlock()
		return errors.New("forwarder is closing")
	}
	if f.server != nil {
		f.mu.Unlock()
		return nil
	}
	// An empty auth key is valid when Configure found an enrolled state
	// directory. tsnet then restores the existing node identity from Dir.
	if f.stateDir == "" {
		f.mu.Unlock()
		return errors.New("forwarder is not configured")
	}
	server = &tsnet.Server{
		AuthKey:  f.authKey,
		Hostname: f.hostname,
		Dir:      f.stateDir,
		Logf:     func(string, ...any) {},
		UserLogf: func(string, ...any) {},
	}
	ctx, cancel := context.WithTimeout(context.Background(), defaultConnectTimeout)
	f.connectCancel = cancel
	// Android does not provide the Unix cache/temp locations that Tailscale's
	// log policy normally discovers. Reuse the app-private tsnet directory.
	if err := os.Setenv("TS_LOGS_DIR", f.stateDir); err != nil {
		f.mu.Unlock()
		return fmt.Errorf("set tsnet log directory: %w", err)
	}
	f.phase = "connecting"
	f.lastErr = ""
	f.mu.Unlock()

	if err := server.Start(); err != nil {
		return fmt.Errorf("start tsnet: %w", err)
	}
	if _, err := server.Up(ctx); err != nil {
		return fmt.Errorf("bring tsnet up: %w", err)
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(f.stateDir, persistedLoginMarker), nil, 0o600); err != nil {
		return fmt.Errorf("persist tsnet enrollment marker: %w", err)
	}

	ip4, ip6 := server.TailscaleIPs()
	addresses := []string{}
	for _, ip := range []netip.Addr{ip4, ip6} {
		if ip.IsValid() {
			addresses = append(addresses, ip.String())
		}
	}
	f.mu.Lock()
	f.server = server
	f.authKey = ""
	f.addresses = addresses
	f.phase = "connected"
	f.lastErr = ""
	f.mu.Unlock()
	return nil
}

// HasPersistedLogin reports whether a previous Connect completed successfully
// for the supplied state directory.
func (f *Forwarder) HasPersistedLogin(stateDir string) bool {
	stateDir = strings.TrimSpace(stateDir)
	if stateDir == "" {
		return false
	}
	info, err := os.Stat(filepath.Join(filepath.Clean(stateDir), persistedLoginMarker))
	return err == nil && !info.IsDir()
}

// StartForward binds a loopback listener. A localPort of zero selects an
// available ephemeral port. The returned Forward contains the chosen port.
func (f *Forwarder) StartForward(remoteHost string, remotePort, localPort int) (ret Forward, err error) {
	f.lifecycle.Lock()
	defer f.lifecycle.Unlock()
	defer func() {
		if recovered := recover(); recovered != nil {
			err = fmt.Errorf("start forward panic: %v", recovered)
			f.setError(err)
		}
	}()
	remoteHost = strings.TrimSpace(remoteHost)
	if remoteHost == "" {
		return Forward{}, errors.New("remote host is required")
	}
	if remotePort < 1 || remotePort > 65535 {
		return Forward{}, fmt.Errorf("invalid remote port %d", remotePort)
	}
	if localPort < 0 || localPort > 65535 {
		return Forward{}, fmt.Errorf("invalid local port %d", localPort)
	}

	f.mu.RLock()
	server := f.server
	f.mu.RUnlock()
	if server == nil {
		return Forward{}, errors.New("tsnet is not connected")
	}

	listener, err := net.Listen("tcp", net.JoinHostPort("127.0.0.1", fmt.Sprint(localPort)))
	if err != nil {
		return Forward{}, fmt.Errorf("listen on local port %d: %w", localPort, err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	result := Forward{
		ID:         net.JoinHostPort(remoteHost, fmt.Sprint(remotePort)) + "->" + listener.Addr().String(),
		RemoteHost: remoteHost,
		RemotePort: remotePort,
		LocalPort:  listener.Addr().(*net.TCPAddr).Port,
	}
	item := &forward{Forward: result, listener: listener, cancel: cancel, done: make(chan struct{})}

	f.mu.RLock()
	active := f.server != nil
	f.mu.RUnlock()
	if !active {
		cancel()
		_ = listener.Close()
		return Forward{}, errors.New("tsnet was closed")
	}
	f.forwardMu.Lock()
	f.forwards[result.ID] = item
	f.forwardMu.Unlock()

	go f.acceptLoop(ctx, server, item)
	return result, nil
}

// StartForwardID is the gomobile-friendly form of StartForward. It returns a
// string ID; use GetForwardLocalPort to retrieve the selected local port.
func (f *Forwarder) StartForwardID(remoteHost string, remotePort, localPort int) (string, error) {
	item, err := f.StartForward(remoteHost, remotePort, localPort)
	if err != nil {
		return "", err
	}
	return item.ID, nil
}

// GetForwardLocalPort returns the local port assigned to a forward ID.
func (f *Forwarder) GetForwardLocalPort(id string) int {
	f.forwardMu.RLock()
	defer f.forwardMu.RUnlock()
	if item, ok := f.forwards[id]; ok {
		return item.LocalPort
	}
	return 0
}

func (f *Forwarder) acceptLoop(ctx context.Context, server *tsnet.Server, item *forward) {
	defer func() {
		if recovered := recover(); recovered != nil {
			f.setError(fmt.Errorf("forward accept panic: %v", recovered))
		}
	}()
	defer func() {
		item.cancel()
		_ = item.listener.Close()
		item.workers.Wait()
		f.forwardMu.Lock()
		delete(f.forwards, item.ID)
		f.forwardMu.Unlock()
		close(item.done)
	}()

	for {
		localConn, err := item.listener.Accept()
		if err != nil {
			select {
			case <-ctx.Done():
				return
			default:
			}
			f.setError(fmt.Errorf("accept forward %s: %w", item.ID, err))
			return
		}
		item.workers.Add(1)
		go func() {
			defer item.workers.Done()
			f.proxy(ctx, server, item, localConn)
		}()
	}
}

func (f *Forwarder) proxy(parent context.Context, server *tsnet.Server, item *forward, local net.Conn) {
	defer func() {
		if recovered := recover(); recovered != nil {
			f.setError(fmt.Errorf("forward proxy panic: %v", recovered))
		}
	}()
	defer local.Close()
	ctx, cancel := context.WithTimeout(parent, defaultDialTimeout)
	defer cancel()
	remote, err := server.Dial(ctx, "tcp", net.JoinHostPort(item.RemoteHost, fmt.Sprint(item.RemotePort)))
	if err != nil {
		if parent.Err() == nil {
			f.setError(fmt.Errorf("dial %s:%d: %w", item.RemoteHost, item.RemotePort, err))
		}
		return
	}
	defer remote.Close()

	proxyConnections(parent, local, remote)
}

func proxyConnections(ctx context.Context, local, remote net.Conn) {
	done := make(chan struct{}, 2)
	go func() { _, _ = io.Copy(remote, local); done <- struct{}{} }()
	go func() { _, _ = io.Copy(local, remote); done <- struct{}{} }()
	completed := 0
	select {
	case <-done:
		completed++
	case <-ctx.Done():
	}
	_ = local.Close()
	_ = remote.Close()
	for completed < 2 {
		<-done
		completed++
	}
}

// StopForward closes one listener and waits for its accept loop to exit.
func (f *Forwarder) StopForward(id string) error {
	f.lifecycle.Lock()
	defer f.lifecycle.Unlock()
	return f.stopForward(id)
}

func (f *Forwarder) stopForward(id string) error {
	f.forwardMu.RLock()
	item, ok := f.forwards[id]
	f.forwardMu.RUnlock()
	if !ok {
		return nil
	}
	item.cancel()
	_ = item.listener.Close()
	<-item.done
	return nil
}

// StopAll closes all active loopback forwards.
func (f *Forwarder) StopAll() {
	f.lifecycle.Lock()
	defer f.lifecycle.Unlock()
	f.stopAll()
}

func (f *Forwarder) stopAll() {
	f.forwardMu.RLock()
	ids := make([]string, 0, len(f.forwards))
	for id := range f.forwards {
		ids = append(ids, id)
	}
	f.forwardMu.RUnlock()
	for _, id := range ids {
		_ = f.stopForward(id)
	}
}

// Status returns a copy of the current forwarder state.
func (f *Forwarder) Status() State {
	f.mu.RLock()
	f.forwardMu.RLock()
	forwardCount := len(f.forwards)
	f.forwardMu.RUnlock()
	state := State{
		Phase:          f.phase,
		Hostname:       f.hostname,
		ForwardCount:   forwardCount,
		LastError:      f.lastErr,
		LocalAddresses: append([]string(nil), f.addresses...),
	}
	f.mu.RUnlock()
	return state
}

// GetPhase returns the current lifecycle phase.
func (f *Forwarder) GetPhase() string { return f.Status().Phase }

// GetHostname returns the configured tsnet hostname.
func (f *Forwarder) GetHostname() string { return f.Status().Hostname }

// GetForwardCount returns the number of active loopback forwards.
func (f *Forwarder) GetForwardCount() int { return f.Status().ForwardCount }

// GetLastError returns the last connection or forwarding error.
func (f *Forwarder) GetLastError() string { return f.Status().LastError }

// GetTailscaleIPv4 returns the first assigned Tailscale IPv4 address.
func (f *Forwarder) GetTailscaleIPv4() string {
	addresses := f.Status().LocalAddresses
	for _, address := range addresses {
		if strings.Contains(address, ".") {
			return address
		}
	}
	return ""
}

// GetTailscaleIPv6 returns the first assigned Tailscale IPv6 address.
func (f *Forwarder) GetTailscaleIPv6() string {
	addresses := f.Status().LocalAddresses
	for _, address := range addresses {
		if strings.Contains(address, ":") {
			return address
		}
	}
	return ""
}

// Interrupt cancels a pending enrollment without waiting for server teardown.
func (f *Forwarder) Interrupt() {
	f.mu.RLock()
	cancel := f.connectCancel
	f.mu.RUnlock()
	if cancel != nil {
		cancel()
	}
}

// Close stops all forwards and closes the tsnet server. It is idempotent.
func (f *Forwarder) Close() {
	f.requestClose()
	f.lifecycle.Lock()
	defer f.lifecycle.Unlock()
	f.close()
}

func (f *Forwarder) requestClose() {
	f.mu.Lock()
	f.closing++
	cancel := f.connectCancel
	f.mu.Unlock()
	if cancel != nil {
		cancel()
	}
}

// close runs with lifecycle held, after requestClose cancels any pending Up.
func (f *Forwarder) close() {
	f.stopAll()
	f.mu.Lock()
	server := f.server
	f.server = nil
	f.addresses = nil
	f.phase = "closed"
	f.closing--
	f.mu.Unlock()
	if server != nil {
		_ = server.Close()
	}
}

// ClearState prevents a concurrent reconnect from resurrecting a deleted identity.
func (f *Forwarder) ClearState() error {
	f.requestClose()
	f.lifecycle.Lock()
	defer f.lifecycle.Unlock()
	f.close()
	f.mu.Lock()
	defer f.mu.Unlock()
	stateDir := f.stateDir
	f.authKey = ""
	f.hostname = ""
	f.stateDir = ""
	f.lastErr = ""
	if stateDir == "" {
		return nil
	}
	return os.RemoveAll(stateDir)
}

var credentialPattern = regexp.MustCompile(`tskey-[A-Za-z0-9_-]+`)

func (f *Forwarder) setError(err error) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.lastErr = credentialPattern.ReplaceAllString(err.Error(), "[redacted]")
	if f.authKey != "" {
		f.lastErr = strings.ReplaceAll(f.lastErr, f.authKey, "[redacted]")
	}
	f.phase = "error"
	return errors.New(f.lastErr)
}
