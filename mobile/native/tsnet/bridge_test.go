package nativetsnet

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestStatusDoesNotExposeCredentials(t *testing.T) {
	client := NewClient()
	if err := client.Configure("tskey-auth-test-secret", "phone", t.TempDir()); err != nil {
		t.Fatal(err)
	}
	var state map[string]any
	if err := json.Unmarshal([]byte(client.Status()), &state); err != nil {
		t.Fatal(err)
	}
	if state["phase"] != "configured" || state["hostname"] != "phone" {
		t.Fatalf("unexpected state: %v", state)
	}
	if strings.Contains(client.Status(), "test-secret") {
		t.Fatal("status exposed the auth key")
	}
}

func TestClearStateRequiresNewEnrollment(t *testing.T) {
	client := NewClient()
	directory := filepath.Join(t.TempDir(), "tsnet")
	if err := client.Configure("tskey-auth-test", "phone", directory); err != nil {
		t.Fatal(err)
	}
	if err := client.ClearState(); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(directory); !os.IsNotExist(err) {
		t.Fatalf("state directory remains: %v", err)
	}
	if err := client.Connect(); err == nil || !strings.Contains(err.Error(), "not configured") {
		t.Fatalf("cleared state retained reusable credentials: %v", err)
	}
	if err := client.ClearState(); err != nil {
		t.Fatalf("repeated cleanup failed: %v", err)
	}
	if err := client.Configure("", "phone", directory); err == nil {
		t.Fatal("cleared state reused missing credentials")
	}
}
