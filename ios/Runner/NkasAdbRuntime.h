#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NkasAdbRuntime : NSObject
@property(class, nonatomic, readonly) NkasAdbRuntime *shared;
// Preserve the port result while importing NSError as a Swift throwing method.
- (NSInteger)startWithError:(NSError * _Nullable * _Nullable)error __attribute__((swift_error(nonnull_error)));
@end

NS_ASSUME_NONNULL_END
