// Only linked during the build; this executable is never run or shipped.
#include "AdbMobile.h"
int main() { return nkas_adb_start_server("tcp:127.0.0.1:5037"); }
