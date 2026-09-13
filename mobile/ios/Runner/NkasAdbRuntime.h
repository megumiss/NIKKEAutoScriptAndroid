#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NkasAdbRuntime : NSObject
@property(class, nonatomic, readonly) NkasAdbRuntime *shared;
- (NSInteger)startWithError:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
