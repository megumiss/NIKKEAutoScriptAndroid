#import "NkasAdbRuntime.h"
#import <netinet/in.h>
#import <stdlib.h>
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
    // iOS 沙盒不允许在容器根目录（NSHomeDirectory()）直接创建文件，
    // ADB 主目录放到可写的 Application Support 下
    NSURL *appSupport = [files URLForDirectory:NSApplicationSupportDirectory
                                      inDomain:NSUserDomainMask
                             appropriateForURL:nil create:YES error:error];
    if (!appSupport) return 0;
    NSURL *adbHome = [appSupport URLByAppendingPathComponent:@"adb" isDirectory:YES];
    if (![files createDirectoryAtURL:adbHome withIntermediateDirectories:YES
                         attributes:@{NSFilePosixPermissions: @0700} error:error]) return 0;
    NSURL *keyDirectory = [adbHome URLByAppendingPathComponent:@".android" isDirectory:YES];
    if (![files createDirectoryAtURL:keyDirectory withIntermediateDirectories:YES
                         attributes:@{NSFilePosixPermissions: @0700} error:error]) return 0;
    if (![keyDirectory setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:error]) return 0;
    // 嵌入式 adb 原生库经 $HOME/.android 定位密钥，重定向到可写目录
    setenv("HOME", adbHome.fileSystemRepresentation, 1);

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
      const char *native = nkas_adb_last_error();
      if (!failure && native && *native) failure = @(native);
      NSString *message = failure
          ? [NSString stringWithFormat:@"ADB 原生库初始化失败：%@", failure]
          : @"ADB 原生库初始化失败，请重试";
      if (error) *error = [NSError errorWithDomain:@"NkasAdb" code:result
                                         userInfo:@{NSLocalizedDescriptionKey: message}];
      return 0;
    }
    _port = port;
    return port;
  }
}
@end
