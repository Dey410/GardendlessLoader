#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs a block and converts any Objective-C exception into a recoverable
/// failure instead of letting it abort the process.
///
/// Swift cannot catch Objective-C exceptions, while several AVAudioEngine APIs
/// raise NSExceptions (for example "required condition is false:
/// inputNode != nullptr || outputNode != nullptr") instead of returning an
/// NSError. Wrapping those calls in this guard keeps a single audio-engine
/// invariant failure from crashing the whole app; callers degrade to the
/// WebKit audio fallback.
@interface NativeSfxExceptionGuard : NSObject

/// Returns nil when `block` completed without raising an Objective-C
/// exception. On an exception, returns a human-readable reason string.
+ (NSString * _Nullable)runBlock:(void (NS_NOESCAPE ^)(void))block
    NS_SWIFT_NAME(runBlock(_:));

@end

NS_ASSUME_NONNULL_END
