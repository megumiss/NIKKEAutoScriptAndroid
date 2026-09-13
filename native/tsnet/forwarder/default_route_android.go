package tsnetforwarder

import "tailscale.com/net/netmon"

func updateAndroidDefaultRouteInterface(ifName string) {
	netmon.UpdateLastKnownDefaultRouteInterface(ifName)
}
