// Copyright 2026 NKAS Mobile contributors. Licensed under Apache-2.0.
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Starts one in-process server on a loopback smart socket. Returns zero when ready.
int nkas_adb_start_server(const char *socket_spec);
void adb_connect_status_updated(const char *serial, const char *status);

#ifdef __cplusplus
}
#endif
