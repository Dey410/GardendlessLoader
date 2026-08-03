#ifndef WebKitHighRefreshRate_h
#define WebKitHighRefreshRate_h

#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

// Uses WebKit SPI and is suitable only for sideloaded builds. The runtime
// checks keep the app working if Apple renames or removes these selectors.
NS_INLINE BOOL GDLDisableWebKit60FPSPreference(
    WKWebViewConfiguration *configuration) {
  WKPreferences *preferences = configuration.preferences;
  Class preferencesClass = [preferences class];
  SEL featuresSelector = NSSelectorFromString(@"_features");
  SEL setEnabledSelector =
      NSSelectorFromString(@"_setEnabled:forFeature:");
  SEL isEnabledSelector =
      NSSelectorFromString(@"_isEnabledForFeature:");
  SEL keySelector = NSSelectorFromString(@"key");

  if (![preferencesClass respondsToSelector:featuresSelector] ||
      ![preferences respondsToSelector:setEnabledSelector] ||
      ![preferences respondsToSelector:isEnabledSelector]) {
    return NO;
  }

  IMP featuresImplementation =
      [preferencesClass methodForSelector:featuresSelector];
  NSArray *(*featuresFunction)(id, SEL) =
      (NSArray *(*)(id, SEL))featuresImplementation;
  NSArray *features = featuresFunction(preferencesClass, featuresSelector);

  for (id feature in features) {
    if (![feature respondsToSelector:keySelector]) {
      continue;
    }
    NSString *key = [feature valueForKey:@"key"];
    if (![key isEqualToString:
                 @"PreferPageRenderingUpdatesNear60FPSEnabled"]) {
      continue;
    }

    IMP setEnabledImplementation =
        [preferences methodForSelector:setEnabledSelector];
    void (*setEnabledFunction)(id, SEL, BOOL, id) =
        (void (*)(id, SEL, BOOL, id))setEnabledImplementation;
    setEnabledFunction(
        preferences,
        setEnabledSelector,
        NO,
        feature);

    IMP isEnabledImplementation =
        [preferences methodForSelector:isEnabledSelector];
    BOOL (*isEnabledFunction)(id, SEL, id) =
        (BOOL (*)(id, SEL, id))isEnabledImplementation;
    return !isEnabledFunction(
        preferences,
        isEnabledSelector,
        feature);
  }

  return NO;
}

#endif /* WebKitHighRefreshRate_h */
