// Package nativetsnet exposes only gomobile-compatible values to Flutter hosts.
package nativetsnet

import (
	"encoding/json"

	"github.com/megumiss/nkas/mobile/native/tsnet/forwarder"
)

type Client struct {
	core *tsnetforwarder.Forwarder
}

func NewClient() *Client { return &Client{core: tsnetforwarder.New()} }

func (c *Client) Configure(authKey, hostname, stateDir string) error {
	return c.core.Configure(authKey, hostname, stateDir)
}

func (c *Client) Connect() error { return c.core.Connect() }

func (c *Client) StartForward(remoteHost string, remotePort, localPort int) (string, error) {
	item, err := c.core.StartForward(remoteHost, remotePort, localPort)
	if err != nil {
		return "", err
	}
	value, err := json.Marshal(map[string]any{
		"id": item.ID, "remoteHost": item.RemoteHost, "remotePort": item.RemotePort, "localPort": item.LocalPort,
	})
	return string(value), err
}

func (c *Client) StopForward(id string) error            { return c.core.StopForward(id) }
func (c *Client) StopAll()                               { c.core.StopAll() }
func (c *Client) Close()                                 { c.core.Close() }
func (c *Client) HasPersistedLogin(stateDir string) bool { return c.core.HasPersistedLogin(stateDir) }
func (c *Client) SetAndroidNetworkInterfaces(payload, defaultInterface string) error {
	return c.core.SetAndroidNetworkInterfaces(payload, defaultInterface)
}

func (c *Client) Status() string {
	state := c.core.Status()
	value, _ := json.Marshal(map[string]any{
		"phase": state.Phase, "hostname": state.Hostname, "addresses": state.LocalAddresses,
		"forwardCount": state.ForwardCount, "error": state.LastError,
	})
	return string(value)
}

func (c *Client) ClearState() error {
	return c.core.ClearState()
}
