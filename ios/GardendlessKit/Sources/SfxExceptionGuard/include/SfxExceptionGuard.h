#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs a block and converts any Objective-C exception into a recoverable
/// failure. AVAudioEngine APIs can raise NSExceptions instead of returning
/// NSError; callers degrade to the WebKit audio fallback.
@interface SfxExceptionGuard : NSObject

+ (NSString * _Nullable)runBlock:(void (NS_NOESCAPE ^)(void))block
    NS_SWIFT_NAME(runBlock(_:));

@end

NS_ASSUME_NONNULL_END
