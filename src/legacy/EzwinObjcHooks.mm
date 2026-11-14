#import "legacy/EzwinHooks.h"
#import <objc/runtime.h>
#include <string.h>

static IMP originals[20];
static Class installedTargets[20];
static unsigned repairCounts[20];
static IMP displacedImplementations[20];
// Runtime routes resolve by name; legacy analysis RVAs are never used for installation.
struct NativeObjcRoute { const char *className,*selector; BOOL classMethod; };
static const NativeObjcRoute nativeRoutes[]={
    {"NSURL","initFileURLWithPath:",NO},
    {"NSFileManager","isWritableFileAtPath:",NO},
    {"AFSDKRCSettings","bundleIdentifier",NO},
    {"NSBundle","bundleIdentifier",NO},
    {"NSBundle","infoDictionary",NO},
    {"UnityAppController","application:didFinishLaunchingWithOptions:",NO},
    {"NSBundle","bundlePath",NO},
    {"NSFileManager","contentsOfDirectoryAtPath:error:",NO},
    {"NSBundle","pathForResource:ofType:",NO},
    {"NSBundle","URLForResource:withExtension:",NO},
    {"NSData","initWithContentsOfURL:options:error:",NO},
    {"NSString","stringWithContentsOfFile:encoding:error:",YES},
    {"NSFileManager","fileExistsAtPath:",NO},
    {"NSFileManager","fileExistsAtPath:isDirectory:",NO},
    {"NSURL","fileURLWithPath:",YES},
    {"UIImage","imageWithContentsOfFile:",YES},
    {"NSData","dataWithContentsOfFile:",YES},
    {"DCAppAttestService","generateKeyWithCompletionHandler:",NO},
    {"DCAppAttestService","attestKey:clientDataHash:completionHandler:",NO},
    {"DCAppAttestService","generateAssertion:clientDataHash:completionHandler:",NO},
};
static const size_t nativeRouteCount=sizeof(nativeRoutes)/sizeof(nativeRoutes[0]);
static_assert(nativeRouteCount==20,"Native Objective-C body/route order");

static NSString *const bundleIdentifier = @"com.criticalforceentertainment.criticalops";

static BOOL blocked(NSString *path) {
    const char *text = path.UTF8String;
    return text && (!Ezwin_IsVisiblePath(text) || strstr(text, "zsjaje374ua") || strstr(text,"libezwin-cracked"));
}

static void missingFile(NSError **error) {
    if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:nil];
}

typedef id (*Object0)(id, SEL);
typedef id (*Object1)(id, SEL, id);
typedef id (*Object2)(id, SEL, id, id);
typedef id (*ReadURL)(__attribute__((ns_consumed)) id, SEL, NSURL *, NSUInteger, NSError **) NS_RETURNS_RETAINED;
typedef id (*InitURL)(__attribute__((ns_consumed)) id, SEL, NSString *) NS_RETURNS_RETAINED;

static id initFileURL(__attribute__((ns_consumed)) id self, SEL command, NSString *path) NS_RETURNS_RETAINED;
static id initFileURL(__attribute__((ns_consumed)) id self, SEL command, NSString *path) {
    return ((InitURL)originals[0])(self, command, path);
}

static BOOL writableFile(id self, SEL command, NSString *path) {
    if (path && blocked(path)) return NO;
    return originals[1] ? ((BOOL (*)(id, SEL, NSString *))originals[1])(self, command, path) : YES;
}

static NSString *identifier(id self, SEL command, size_t index) {
    NSString *value = ((Object0)originals[index])(self, command);
    if ([value hasPrefix:bundleIdentifier]) return bundleIdentifier;
    return ((Object0)originals[index])(self, command);
}

static NSString *sdkIdentifier(id self, SEL command) { return identifier(self, command, 2); }
static NSString *bundleID(id self, SEL command) { return identifier(self, command, 3); }

static NSDictionary *infoDictionary(id self, SEL command) {
    NSMutableDictionary *info = [((Object0)originals[4])(self, command) mutableCopy];
    NSString *value = info[@"CFBundleIdentifier"];
    if ([value hasPrefix:bundleIdentifier]) info[@"CFBundleIdentifier"] = bundleIdentifier;
    return info;
}

static BOOL didFinishLaunching(id self, SEL command, id application, NSDictionary *options) {
    return ((BOOL (*)(id, SEL, id, NSDictionary *))originals[5])(self, command, application, options);
}

static NSString *bundlePath(id self, SEL command) { return ((Object0)originals[6])(self, command); }

static NSArray *directoryContents(id self, SEL command, NSString *path, NSError **error) {
    if (blocked(path)) { missingFile(error); return nil; }
    NSArray *items = ((NSArray *(*)(id, SEL, NSString *, NSError **))originals[7])(self, command, path, error);
    if (![path containsString:@"Application"] || !items) return items;
    NSMutableArray *visible = [NSMutableArray arrayWithCapacity:items.count];
    for (NSString *item in items) {
        const char *name = item.UTF8String;
        if (!Ezwin_IsVisiblePath(name) || [item containsString:@"udcops"] ||
            [item containsString:@"libezwin-cracked"] ||
            [item containsString:@"SignedByEsign"] || [item containsString:@"embedded"] ||
            [item containsString:@"mobileprovision"]) continue;
        [visible addObject:item];
    }
    return visible;
}

static BOOL hiddenResource(NSString *name, NSString *extension, BOOL isURL) {
    if ([name containsString:@"SignedByEsign"] || [name containsString:@"embedded"] ||
        [name containsString:@"libezwin-cracked"] ||
        [extension containsString:@"mobileprovision"]) return YES;
    return isURL && ([extension containsString:@".dylib"] || [name containsString:@"udcops"]);
}

static NSString *resourcePath(id self, SEL command, NSString *name, NSString *extension) {
    return hiddenResource(name, extension, NO) ? nil : ((Object2)originals[8])(self, command, name, extension);
}

static NSURL *resourceURL(id self, SEL command, NSString *name, NSString *extension) {
    return hiddenResource(name, extension, YES) ? nil : ((Object2)originals[9])(self, command, name, extension);
}

static id readURL(__attribute__((ns_consumed)) id self, SEL command, NSURL *url, NSUInteger options,
    NSError **error) NS_RETURNS_RETAINED;
static id readURL(__attribute__((ns_consumed)) id self, SEL command, NSURL *url, NSUInteger options, NSError **error) {
    if (url && blocked(url.path)) { missingFile(error); return nil; }
    return ((ReadURL)originals[10])(self, command, url, options, error);
}

static NSString *readString(id self, SEL command, NSString *path, NSStringEncoding encoding, NSError **error) {
    if (blocked(path)) { missingFile(error); return nil; }
    return ((NSString *(*)(id, SEL, NSString *, NSStringEncoding, NSError **))originals[11])(
        self, command, path, encoding, error);
}

static BOOL fileExists(id self, SEL command, NSString *path) {
    return path && !blocked(path) && ((BOOL (*)(id, SEL, NSString *))originals[12])(self, command, path);
}

static BOOL fileExistsDirectory(id self, SEL command, NSString *path, BOOL *directory) {
    if (blocked(path)) { if (directory) *directory = NO; return NO; }
    return ((BOOL (*)(id, SEL, NSString *, BOOL *))originals[13])(self, command, path, directory);
}

static NSURL *fileURL(id self, SEL command, NSString *path) { return ((Object1)originals[14])(self, command, path); }
static id imageFromFile(id self, SEL command, NSString *path) {
    return blocked(path) ? nil : ((Object1)originals[15])(self, command, path);
}
static NSData *dataFromFile(id self, SEL command, NSString *path) {
    return blocked(path) ? nil : ((Object1)originals[16])(self, command, path);
}

// These client entry points preserve the original App Attest service and completion handlers.
static void generateKey(id self, SEL command, void (^completion)(NSString *, NSError *)) {
    ((void (*)(id, SEL, id))originals[17])(self, command, completion);
}
static void attestKey(id self, SEL command, NSString *key, NSData *hash, void (^completion)(NSData *, NSError *)) {
    ((void (*)(id, SEL, id, id, id))originals[18])(self, command, key, hash, completion);
}
static void assertion(id self, SEL command, NSString *key, NSData *hash, void (^completion)(NSData *, NSError *)) {
    ((void (*)(id, SEL, id, id, id))originals[19])(self, command, key, hash, completion);
}

static IMP bodies[20] = {
    (IMP)initFileURL, (IMP)writableFile, (IMP)sdkIdentifier, (IMP)bundleID, (IMP)infoDictionary,
    (IMP)didFinishLaunching, (IMP)bundlePath, (IMP)directoryContents, (IMP)resourcePath, (IMP)resourceURL,
    (IMP)readURL, (IMP)readString, (IMP)fileExists, (IMP)fileExistsDirectory, (IMP)fileURL,
    (IMP)imageFromFile, (IMP)dataFromFile, (IMP)generateKey, (IMP)attestKey, (IMP)assertion
};

BOOL Ezwin_ReplaceObjcMethod(Class target, SEL selector, IMP replacement, IMP *original) {
    if (!target || !selector || !replacement || !original) return NO;
    Method method = class_getInstanceMethod(target, selector);
    if (!method) return NO;
    IMP current = method_getImplementation(method);
    if (current == replacement) return NO;
    *original = current;
    const char *types = method_getTypeEncoding(method);
    if (!class_addMethod(target, selector, replacement, types)) class_replaceMethod(target, selector, replacement, types);
    return YES;
}

NSDictionary *Ezwin_InstallNativeObjcHooks(void) {
    NSMutableDictionary *saved = [NSMutableDictionary dictionary];
    NSMutableArray *installed = [NSMutableArray array], *missing = [NSMutableArray array];
    NSMutableArray *repaired=[NSMutableArray array],*pending=[NSMutableArray array];
    NSMutableDictionary *repairs=[NSMutableDictionary dictionary],*displaced=[NSMutableDictionary dictionary];
    NSMutableDictionary *reasons=[NSMutableDictionary dictionary];
    const unsigned arguments[20]={3,3,2,2,2,4,2,4,4,4,5,5,3,4,3,3,3,3,5,5};
    @synchronized ([NSProcessInfo processInfo]) {
        for (size_t i = 0; i < nativeRouteCount; ++i) {
            const NativeObjcRoute *hook = nativeRoutes + i;
            NSString *name = [NSString stringWithFormat:@"%s %s", hook->className, hook->selector];
            Class target=objc_getClass(hook->className);
            if(target && hook->classMethod)target=object_getClass(target);
            SEL selector=sel_registerName(hook->selector);
            Method method=target?class_getInstanceMethod(target,selector):nullptr;
            BOOL success=NO;
            if(!target) { reasons[name]=@"Class not loaded";[pending addObject:name]; }
            else if(!method)reasons[name]=@"Selector unavailable";
            else if(method_getNumberOfArguments(method)!=arguments[i])reasons[name]=@"Method ABI mismatch";
            else if(installedTargets[i] && installedTargets[i]!=target)
                reasons[name]=@"Target class changed after installation";
            else if(installedTargets[i] && originals[i]) {
                IMP current=method_getImplementation(method);
                if(current==bodies[i])success=YES;
                else {
                    // A later hook may have saved our body as its original.
                    // Never adopt that later IMP as originals[i]: doing so
                    // would create body -> later hook -> body recursion.
                    // Reassert our method while retaining the first original.
                    displacedImplementations[i]=class_replaceMethod(target,selector,bodies[i],method_getTypeEncoding(method));
                    success=class_getMethodImplementation(target,selector)==bodies[i];
                    if(success) { ++repairCounts[i];[repaired addObject:name]; }
                    else reasons[name]=@"Replacement changed during recovery";
                }
            }
            else if(Ezwin_ReplaceObjcMethod(target,selector,bodies[i],&originals[i])) {
                installedTargets[i]=target;success=YES;
            } else reasons[name]=@"Replacement not installed";
            if(success)saved[name]=@((uintptr_t)originals[i]);
            if(repairCounts[i])repairs[name]=@(repairCounts[i]);
            if(displacedImplementations[i])displaced[name]=@((uintptr_t)displacedImplementations[i]);
            [(success ? installed : missing) addObject:name];
        }
    }
    return @{@"enabled":@YES,@"planned":@(nativeRouteCount),@"installed":installed, @"missing":missing,
        @"missingReasons":reasons,@"originals":saved,@"repaired":repaired,@"repairCounts":repairs,
        @"pending":pending,@"displacedImplementations":displaced,
        @"recoveryMode":@"Reasserts owned methods and retains first originals; later wrappers are not adopted",
        @"appAttestMode":@"Original service and completion handlers forwarded"};
}

#ifdef EZWIN_HOOK_TESTING
extern "C" IMP EzwinTestObjcBody(size_t index) { return index < 20 ? bodies[index] : nullptr; }
extern "C" void EzwinTestObjcOriginal(size_t index, IMP original) { if (index < 20) originals[index] = original; }
extern "C" BOOL EzwinTestObjcBlocked(NSString *path) { return blocked(path); }
#endif
