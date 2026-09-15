// Only linked during the build; this executable is never run or shipped.
#include "AdbMobile.h"
int main() { return nkas_adb_start_server("tcp:localhost:5037"); }
