// Copyright 2026 NKAS Mobile contributors. Licensed under Apache-2.0.
#include <condition_variable>
#include <stdexcept>

int adb_server_main(int is_daemon, const std::string& socket_spec, const char* one_device, int ack_reply_fd);

namespace {
enum class NkasAdbState { idle, starting, ready, failed };
std::mutex nkas_start_mutex;
std::condition_variable nkas_start_changed;
NkasAdbState nkas_start_state = NkasAdbState::idle;
std::string nkas_socket_spec;

void nkas_adb_ready() {
    std::lock_guard<std::mutex> lock(nkas_start_mutex);
    nkas_start_state = NkasAdbState::ready;
    nkas_start_changed.notify_all();
}
}

extern "C" int nkas_adb_start_server(const char* socket_spec) {
    if (!socket_spec || std::string_view(socket_spec).find("tcp:127.0.0.1:") != 0) return -1;
    std::unique_lock<std::mutex> lock(nkas_start_mutex);
    if (nkas_start_state == NkasAdbState::idle) {
        nkas_socket_spec = socket_spec;
        nkas_start_state = NkasAdbState::starting;
        try {
            std::thread([] {
                try {
                    adb_server_main(false, nkas_socket_spec, nullptr, -1);
                } catch (const std::exception& error) {
                    LOG(ERROR) << "Embedded ADB startup failed: " << error.what();
                } catch (...) {
                    LOG(ERROR) << "Embedded ADB startup failed";
                }
                std::lock_guard<std::mutex> guard(nkas_start_mutex);
                nkas_start_state = NkasAdbState::failed;
                nkas_start_changed.notify_all();
            }).detach();
        } catch (...) {
            nkas_start_state = NkasAdbState::failed;
        }
    }
    if (nkas_socket_spec != socket_spec) return -1;
    if (!nkas_start_changed.wait_for(lock, std::chrono::seconds(15), [] {
        return nkas_start_state != NkasAdbState::starting;
    })) return -1;
    return nkas_start_state == NkasAdbState::ready ? 0 : -1;
}
