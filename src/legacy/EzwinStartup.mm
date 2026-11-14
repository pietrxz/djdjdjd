#import "legacy/EzwinHooks.h"
#include <string.h>

static void StartupError(NSString *reason) __attribute__((noreturn));
static void StartupError(NSString *reason) {
    @throw [NSException exceptionWithName:@"EzwinStartup" reason:reason userInfo:nil];
}
size_t Ezwin_RegisterLoadMethods(EzwinObjcAPI api, uint64_t base) {
    // 349 method registrations observed in the +load routines.
    for (size_t i = 0; i < kEzwinMethodCount; i++) {
        const EzwinMethodEntry *method = &kEzwinMethods[i];
        uint64_t cls = api.findClass(api.context,method->className,method->metaclass);
        if (!cls) StartupError(@"Could not find the dylib class");
        api.replaceMethod(api.context,cls,method->selector,Ezwin_Address(base,method->implementation),method->encoding);
    }
    return kEzwinMethodCount;
}
BOOL Ezwin_InstallObjcHook(EzwinObjcAPI api, const EzwinObjcHook *hook,
    uint64_t base, NSMutableDictionary *originals) {
    uint64_t cls = api.findClass(api.context,hook->className,hook->classMethod);
    if (!cls) return NO;
    uint64_t method = api.findMethod(api.context,cls,hook->selector);
    if (!method) return NO;
    const char *types = api.typeEncoding(api.context,method);
    uint64_t replacement = api.replacementBody ? api.replacementBody(api.context,hook) :
        Ezwin_Address(base,hook->replacement);
    if (!replacement) return NO;
    uint64_t inherited = api.implementation ? api.implementation(api.context,method) : 0;
    if (api.prepareBridge) api.prepareBridge(api.context,cls,hook->selector,replacement);
    uint64_t original = api.replaceMethod(api.context,cls,hook->selector,replacement,types);
    if (!original) original = inherited;
    if (!original) return NO;
    originals[@(hook->originalSlot)] = @(original);
    return YES;
}
size_t Ezwin_RebindImage(NSMutableDictionary *image, uint64_t base, NSMutableDictionary *originals) {
    size_t changed = 0;
    for (NSMutableDictionary *entry in image[@"imports"]) {
        const char *name = [entry[@"name"] UTF8String];
        if (*name == '_') name++;
        for (size_t i = 0; i < kEzwinSymbolHookCount; i++) {
            const EzwinSymbolHook *hook = &kEzwinSymbolHooks[i];
            if (strcmp(name,hook->name) != 0) continue;
            uint64_t replacement = Ezwin_Address(base,hook->replacement);
            uint64_t old = [entry[@"value"] unsignedLongLongValue];
            if (old == replacement) break;
            originals[@(hook->originalSlot)] = @(old);
            Ezwin_WritePointer(image,[entry[@"slot"] unsignedLongLongValue],replacement);
            changed++;
            break;
        }
    }
    return changed;
}
NSMutableDictionary *Ezwin_RegisterImageCallback(uint64_t base, void (^registerCallback)(EzwinImageCallback)) {
    NSMutableDictionary *state = [@{@"originals":[NSMutableDictionary dictionary],@"imagesSeen":@0,@"slotsChanged":@0} mutableCopy];
    registerCallback(^(NSMutableDictionary *image) {
        @synchronized (state) {
            size_t changed = Ezwin_RebindImage(image,base,state[@"originals"]);
            state[@"slotsChanged"] = @([state[@"slotsChanged"] unsignedLongLongValue] + changed);
            state[@"imagesSeen"] = @([state[@"imagesSeen"] unsignedLongLongValue] + 1);
        }
    });
    return state;
}
void Ezwin_ReplaceUnityPointer(NSMutableDictionary *image, const EzwinPointerHook *hook,
    uint64_t base, NSMutableDictionary *originals) {
    uint64_t unityBase = [image[@"base"] unsignedLongLongValue];
    uint64_t old = Ezwin_ReadPointer(image,hook->slot);
    if (old != Ezwin_Address(unityBase,hook->expectedOriginal)) StartupError(@"The Unity pointer slot does not match the analyzed file");
    originals[@(hook->originalSlot)] = @(old);
    Ezwin_WritePointer(image,hook->slot,Ezwin_Address(base,hook->replacement));
}
NSMutableDictionary *Ezwin_RunStartup(NSMutableDictionary *unity, uint64_t base,
    EzwinObjcAPI objc, EzwinMachAPI mach, NSArray *processImages) {
    NSMutableDictionary *originals = [NSMutableDictionary dictionary];
    NSMutableArray *external = [NSMutableArray array], *breakpoints = [NSMutableArray array];
    size_t methodCount = Ezwin_RegisterLoadMethods(objc,base), installed = 0, missing = 0;
    // 0402eb14: ObjC hook installation.
    for (size_t i = 0; i < kEzwinObjcHookCount; i++) {
        const EzwinObjcHook *hook = &kEzwinObjcHooks[i];
        if (Ezwin_InstallObjcHook(objc,hook,base,originals)) installed++; else missing++;
        [external addObject:@{@"rva":@(hook->replacement),@"kind":@"ObjC replacement body"}];
    }
    // 040908e8: visible image inventory.
    EzwinOriginals empty = {};
    Ezwin_ConfigureHooks(empty,processImages,base);
    // 040eb6d8: SVC target and three breakpoints.
    NSInteger svc = Ezwin_ScanUnityText(unity,"41 05 00 D4");
    if (svc < 0x24 || (uint64_t)svc - 0x24 != kEzwinBreakpointHooks[0].target) StartupError(@"Unity SVC target mismatch");
    uint32_t capacity = mach.capacity(mach.context);
    if (capacity > 16) capacity = 16;
    if (kEzwinBreakpointCount > capacity) StartupError(@"Insufficient breakpoint capacity");
    mach.configureService(mach.context,0x40,0x80000002,6,0x04790eac,0x048c0c84);
    EzwinDebugState debug = {};
    uint64_t unityBase = [unity[@"base"] unsignedLongLongValue];
    for (size_t i = 0; i < kEzwinBreakpointCount; i++) {
        const EzwinBreakpointHook *hook = &kEzwinBreakpointHooks[i];
        debug.bvr[i] = Ezwin_Address(unityBase,hook->target);
        debug.bcr[i] = 0x1e5;
        mach.setDebugState(mach.context,&debug);
        [breakpoints addObject:@{@"target":@(debug.bvr[i]),@"replacement":@(Ezwin_Address(base,hook->replacement))}];
        [external addObject:@{@"rva":@(hook->replacement),@"kind":@"Breakpoint replacement body"}];
    }
    // 03382194: the identity/file initialization body depends on the runtime.
    // 04757d48: symbols handled through the add-image callback.
    NSMutableDictionary *rebind = Ezwin_RegisterImageCallback(base,^(EzwinImageCallback callback) { callback(unity); });
    [originals addEntriesFromDictionary:rebind[@"originals"]];
    size_t matched = 0;
    for (size_t i = 0; i < kEzwinSymbolHookCount; i++) if (originals[@(kEzwinSymbolHooks[i].originalSlot)]) matched++;
    // 04425064: two Unity pointer slots.
    for (size_t i = 0; i < kEzwinPointerHookCount; i++) {
        const EzwinPointerHook *hook = &kEzwinPointerHooks[i];
        Ezwin_ReplaceUnityPointer(unity,hook,base,originals);
        [external addObject:@{@"rva":@(hook->replacement),@"kind":@"Unity replacement body"}];
    }
    return [@{@"originals":originals,@"methodCount":@(methodCount),@"objcInstalled":@(installed),@"objcMissing":@(missing),
        @"symbolMatched":@(matched),@"slotsChanged":rebind[@"slotsChanged"],@"imageCallbacks":rebind[@"imagesSeen"],
        @"pointerCount":@(kEzwinPointerHookCount),@"breakpoints":breakpoints,@"externalBodies":external,
        @"externalAuxiliary":@[@{@"rva":@0x03382194,@"kind":@"Identity/file initialization"}],
        @"visibleImages":Ezwin_GetVisibleImages()} mutableCopy];
}
