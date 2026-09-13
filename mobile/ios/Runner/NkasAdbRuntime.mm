#import "NkasAdbRuntime.h"
#import <netinet/in.h>
#import <sys/socket.h>
#import <unistd.h>
#include <exception>

extern "C" {
#include <AdbMobile/AdbMobile.h>

void adb_connect_status_updated(const char *serial, const char *status) {
  if (!serial || !status) return;
  NSDictionary *state = @{@"endpoint": @(serial), @"state": @(status)};
  dispatch_async(dispatch_get_main_queue(), ^{
    [NSNotificationCenter.defaultCenter postNotificationName:@"NkasNativeAdbState" object:nil userInfo:state];
  });
}
}

@implementation NkasAdbRuntime {
  NSInteger _port;
}

+ (NkasAdbRuntime *)shared {
  static NkasAdbRuntime *runtime;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ runtime = [NkasAdbRuntime new]; });
  return runtime;
}

- (NSInteger)startWithError:(NSError **)error {
  @synchronized(self) {
    if (_port != 0) return _port;
    NSFileManager *files = NSFileManager.defaultManager;
    NSURL *keyDirectory = [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@".android"]];
    if (![files createDirectoryAtURL:keyDirectory withIntermediateDirectories:YES
                         attributes:@{NSFilePosixPermissions: @0700} error:error]) return 0;
    if (![keyDirectory setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:error]) return 0;

    // The embedded adb server uses the same loopback smart-socket API as desktop adb.
    int probe = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address = {};
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    socklen_t size = sizeof(address);
    if (probe < 0 || bind(probe, (struct sockaddr *)&address, size) != 0 ||
        getsockname(probe, (struct sockaddr *)&address, &size) != 0) {
      if (probe >= 0) close(probe);
      if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
      return 0;
    }
    NSInteger port = ntohs(address.sin_port);
    close(probe);
    NSString *socketSpec = [NSString stringWithFormat:@"tcp:127.0.0.1:%ld", (long)port];
    int result = -1;
    NSString *failure;
    try {
      result = nkas_adb_start_server(socketSpec.UTF8String);
    } catch (const std::exception &exception) {
      failure = @(exception.what());
    } catch (...) {
      failure = @"ADB 原生库初始化失败";
    }
    if (result != 0) {
      if (error) *error = [NSError errorWithDomain:@"NkasAdb" code:result
                                         userInfo:@{NSLocalizedDescriptionKey: failure ?: @"ADB 原生库初始化失败，请重启应用"}];
      return 0;
    }
    _port = port;
    return port;
  }
}
@end
