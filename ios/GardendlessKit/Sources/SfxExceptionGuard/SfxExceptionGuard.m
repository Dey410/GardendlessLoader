#import "SfxExceptionGuard.h"

@implementation SfxExceptionGuard

+ (NSString * _Nullable)runBlock:(void (NS_NOESCAPE ^)(void))block {
  @try {
    block();
    return nil;
  } @catch (NSException *exception) {
    return [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason];
  }
}

@end
