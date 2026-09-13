package tsnetforwarder

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"strings"
	"sync"
	"testing"
	"time"

	"tailscale.com/tsnet"
)

func TestCancelledForwardClosesActiveConnections(t *testing.T) {
	local, localPeer := net.Pipe()
	remote, remotePeer := net.Pipe()
	defer localPeer.Close()
	defer remotePeer.Close()
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { proxyConnections(ctx, local, remote); close(done) }()
	go func() { _, _ = localPeer.Write([]byte("hello")) }()
	var received [5]byte
	if _, err := io.ReadFull(remotePeer, received[:]); err != nil {
		t.Fatal(err)
	}
	if string(received[:]) != "hello" {
		t.Fatalf("unexpected forwarded data %q", received)
	}
	cancel()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("cancel left the forwarding copies blocked")
	}
	for _, conn := range []net.Conn{localPeer, remotePeer} {
		if _, err := conn.Read(make([]byte, 1)); err != io.EOF {
			t.Fatalf("connection still open: %v", err)
		}
	}
}

func TestConcurrentCleanupIsIdempotent(t *testing.T) {
	f := New()
	var workers sync.WaitGroup
	for i := 0; i < 20; i++ {
		workers.Add(1)
		go func() { defer workers.Done(); f.Close(); f.StopAll() }()
	}
	workers.Wait()
	if state := f.Status(); state.Phase != "closed" || state.ForwardCount != 0 {
		t.Fatalf("unexpected final state: %+v", state)
	}
}

func TestStopAllReleasesListeners(t *testing.T) {
	f := New()
	f.server = &tsnet.Server{}
	item, err := f.StartForward("100.64.0.2", 5555, 0)
	if err != nil {
		t.Fatal(err)
	}
	if f.Status().ForwardCount != 1 {
		t.Fatal("listener not tracked")
	}
	f.StopAll()
	f.StopAll()
	listener, err := net.Listen("tcp", net.JoinHostPort("127.0.0.1", fmt.Sprint(item.LocalPort)))
	if err != nil {
		t.Fatalf("stop retained a listening port: %v", err)
	}
	listener.Close()
	if f.Status().ForwardCount != 0 {
		t.Fatal("stopped listener still tracked")
	}
}

func TestErrorsRedactCredentialsEvenAfterEnrollment(t *testing.T) {
	f := New()
	err := f.setError(errors.New("authentication rejected tskey-auth-sensitive-data"))
	if strings.Contains(err.Error(), "sensitive") || strings.Contains(f.Status().LastError, "sensitive") {
		t.Fatal("returned error or state exposed credentials")
	}
}
