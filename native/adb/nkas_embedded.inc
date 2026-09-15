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
std::string nkas_last_error;

void nkas_adb_ready() {
    std::lock_guard<std::mutex> lock(nkas_start_mutex);
    nkas_start_state = NkasAdbState::ready;
    nkas_start_changed.notify_all();
}
}

extern "C" const char* nkas_adb_last_error() {
    std::lock_guard<std::mutex> lock(nkas_start_mutex);
    return nkas_last_error.c_str();
}

extern "C" int nkas_adb_start_server(const char* socket_spec) {
    if (!socket_spec || std::string_view(socket_spec).find("tcp:127.0.0.1:") != 0) return -1;
    std::unique_lock<std::mutex> lock(nkas_start_mutex);
    // 服务线程进入 failed 前已经退出，可以重新开始；starting/ready 复用现有线程
    if (nkas_start_state == NkasAdbState::failed) nkas_start_state = NkasAdbState::idle;
    if (nkas_start_state == NkasAdbState::idle) {
        nkas_socket_spec = socket_spec;
        nkas_last_error.clear();
        nkas_start_state = NkasAdbState::starting;
        try {
            std::thread([] {
                std::string failure;
                try {
                    adb_server_main(false, nkas_socket_spec, nullptr, -1);
                    failure = "ADB 服务意外退出";
                } catch (const std::exception& error) {
                    LOG(ERROR) << "Embedded ADB startup failed: " << error.what();
                    failure = error.what();
                } catch (...) {
                    LOG(ERROR) << "Embedded ADB startup failed";
                }
                std::lock_guard<std::mutex> guard(nkas_start_mutex);
                nkas_last_error = failure;
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
