#import "legacy/EzwinHooks.h"
#include <errno.h>
#include <string.h>
#include <stdlib.h>

// Plain functions using the orig_... / hook_... naming convention.
static int (*orig_fclose)(FILE *);
static int (*orig_unlink)(const char *);
static int (*orig_lstat)(const char *, struct stat *);
static int (*orig_stat)(const char *, struct stat *);
static struct dirent *(*orig_readdir)(DIR *);
static int (*orig_truncate)(const char *, off_t);
static FILE *(*orig_fopen)(const char *, const char *);
static int (*orig_access)(const char *, int);
static int (*orig_open)(const char *, int);
static DIR *(*orig_opendir)(const char *);
static uint64_t (*orig_dlopen)(const char *, int);
static uint64_t (*orig_dlsym)(uint64_t, const char *);
static int (*orig_dladdr)(uint64_t, EzwinDlInfo *);
static int (*orig_task_info)(uint64_t, uint32_t, EzwinTaskInfo *);
static NSString *(*orig_signing_identifier)(uint64_t, uint64_t);
static NSArray *gVisibleImages;
static uint64_t gEzwinBase;
static uint64_t gDecoyHeader;

static void NeedOriginal(BOOL exists, const char *name) {
    if (!exists) @throw [NSException exceptionWithName:@"EzwinMissingOriginal"
        reason:[NSString stringWithFormat:@"Original function not provided: %s", name] userInfo:nil];
}
#define ORIG(name) NeedOriginal(orig_##name != NULL, #name)

void Ezwin_ConfigureHooks(EzwinOriginals originals, NSArray *images, uint64_t base) {
    orig_fclose = originals.fclose;
    orig_unlink = originals.unlink;
    orig_lstat = originals.lstat;
    orig_stat = originals.stat;
    orig_readdir = originals.readdir;
    orig_truncate = originals.truncate;
    orig_fopen = originals.fopen;
    orig_access = originals.access;
    orig_open = originals.open;
    orig_opendir = originals.opendir;
    orig_dlopen = originals.dlopen;
    orig_dlsym = originals.dlsym;
    orig_dladdr = originals.dladdr;
    orig_task_info = originals.taskInfo;
    orig_signing_identifier = originals.signingIdentifier;
    gEzwinBase = base;
    gDecoyHeader = Ezwin_Address(base, 0x04cddc3d);
    NSMutableArray *visible = [NSMutableArray array];
    for (NSDictionary *image in images) {
        NSString *path = image[@"path"];
        if (Ezwin_IsVisiblePath(path.UTF8String)) [visible addObject:image];
    }
    gVisibleImages = [visible copy];
}
NSArray *Ezwin_GetVisibleImages(void) { return gVisibleImages ?: @[]; }

int hook_fclose(FILE *stream) { ORIG(fclose); return orig_fclose(stream); }
int hook_unlink(const char *path) { ORIG(unlink); return orig_unlink(path); }
int hook_lstat(const char *path, struct stat *output) {
    if (!Ezwin_IsVisiblePath(path)) { errno = ENOENT; return -1; }
    ORIG(lstat); return orig_lstat(path, output);
}
int hook_stat(const char *path, struct stat *output) {
    if (!Ezwin_IsVisiblePath(path)) { errno = ENOENT; return -1; }
    ORIG(stat); return orig_stat(path, output);
}
struct dirent *hook_readdir(DIR *directory) {
    ORIG(readdir);
    while (YES) {
        struct dirent *entry = orig_readdir(directory);
        if (!entry || Ezwin_IsVisiblePath(entry->d_name)) return entry;
    }
}
int hook_truncate(const char *path, off_t length) {
    if (!Ezwin_IsVisiblePath(path)) { errno = ENOENT; return -1; }
    ORIG(truncate); return orig_truncate(path, length);
}
FILE *hook_fopen(const char *path, const char *mode) {
    if (!Ezwin_IsVisiblePath(path)) { errno = ENOENT; return NULL; }
    ORIG(fopen); return orig_fopen(path, mode);
}
int hook_access(const char *path, int mode) {
    if (!Ezwin_IsVisiblePath(path)) { errno = ENOENT; return -1; }
    ORIG(access); return orig_access(path, mode);
}
DIR *hook_opendir(const char *path) {
    if (!Ezwin_IsVisiblePath(path)) { errno = ENOENT; return NULL; }
    ORIG(opendir); return orig_opendir(path);
}
int hook_open(const char *path, int flags) {
    // The two arguments observed in the binary. The variadic mode argument has not been verified.
    if (!Ezwin_IsVisiblePath(path)) { errno = ENOENT; return -1; }
    ORIG(open); return orig_open(path, flags);
}
uint64_t hook_dlopen(const char *path, int mode) {
    if (path && !Ezwin_IsVisiblePath(path)) return 0;
    ORIG(dlopen); return orig_dlopen(path, mode);
}

static const EzwinSymbolHook kDyldRoutes[] = {
    {"_dyld_image_count", 0x040de66c, 0},
    {"_dyld_get_image_name", 0x040de7f8, 0},
    {"_dyld_get_image_vmaddr_slide", 0x040de8c4, 0},
    {"_dyld_get_image_header", 0x040de9a0, 0},
};
uint64_t hook_dlsym(uint64_t handle, const char *name) {
    ORIG(dlsym);
    uint64_t original = orig_dlsym(handle, name);
    for (int i = 0; i < 4; i++) {
        if (original == orig_dlsym(handle, kDyldRoutes[i].name))
            return Ezwin_Address(gEzwinBase, kDyldRoutes[i].replacement);
    }
    return orig_dlsym(handle, name);
}
int hook_dladdr(uint64_t address, EzwinDlInfo *output) {
    ORIG(dladdr); ORIG(dlsym);
    int result = orig_dladdr(address, output);
    if (!result) return result;
    const int order[] = {0, 1, 3, 2};
    for (int i = 0; i < 4; i++) {
        const EzwinSymbolHook *route = &kDyldRoutes[order[i]];
        if (address == orig_dlsym(UINT64_MAX, route->name)) {
            output->symbolAddress = Ezwin_Address(gEzwinBase, route->replacement);
            return result;
        }
    }
    if (!Ezwin_IsVisiblePath(output->filename)) {
        memset(output, 0, sizeof(*output));
        return 0;
    }
    return result;
}
uint32_t hook_dyld_image_count(void) { return (uint32_t)gVisibleImages.count; }
const char *hook_dyld_get_image_name(uint32_t index) {
    if (index > gVisibleImages.count) return NULL;
    if (index == gVisibleImages.count) @throw [NSException exceptionWithName:@"EzwinBinaryBoundary"
        reason:@"The binary name accessor reads one element past the end" userInfo:nil];
    return [gVisibleImages[index][@"path"] UTF8String];
}
uint64_t hook_dyld_get_image_header(uint32_t index) {
    if (index >= gVisibleImages.count) return 0;
    NSDictionary *image = gVisibleImages[index];
    uint64_t header = [image[@"header"] unsignedLongLongValue];
    return header && [image[@"fileType"] intValue] == 2 ? gDecoyHeader : header;
}
uint64_t hook_dyld_get_image_vmaddr_slide(uint32_t index) {
    if (index == 0) return gDecoyHeader; // Preserves the observed behavior.
    if (index > gVisibleImages.count) return 0;
    if (index == gVisibleImages.count) @throw [NSException exceptionWithName:@"EzwinBinaryBoundary"
        reason:@"The binary slide accessor reads one element past the end" userInfo:nil];
    return [gVisibleImages[index][@"slide"] unsignedLongLongValue];
}

void Ezwin_FreeTaskInfo(EzwinTaskInfo *info) {
    if (info->ownsBuffers) { free(info->images); free(info->uuids); }
    memset(info, 0, sizeof(*info));
}
void Ezwin_FilterTaskInfo(const EzwinTaskInfo *input, EzwinTaskInfo *output,
    uint64_t decoy, BOOL (*isExecutable)(uint64_t)) {
    EzwinTaskInfo result = {};
    memcpy(result.prefix, input->prefix, sizeof(result.prefix));
    result.images = (EzwinImageInfo *)calloc(0x800, sizeof(EzwinImageInfo));
    result.uuids = (EzwinImageUUID *)calloc(0x800, sizeof(EzwinImageUUID));
    result.ownsBuffers = YES;
    if (!result.images || !result.uuids) { Ezwin_FreeTaskInfo(&result); @throw [NSException exceptionWithName:@"EzwinMemory" reason:@"Could not allocate task info memory" userInfo:nil]; }
    uint64_t retained[0x800] = {};
    uint64_t executable = 0;
    for (size_t i = 0; i < input->imageCount && result.imageCount < 0x800; i++) {
        EzwinImageInfo image = input->images[i];
        if (image.path && !Ezwin_IsVisiblePath(image.path)) continue;
        retained[result.imageCount] = image.header;
        if (image.header && isExecutable(image.header)) { executable = image.header; image.header = decoy; }
        result.images[result.imageCount++] = image;
    }
    for (size_t i = 0; i < input->uuidCount && result.uuidCount < 0x800; i++) {
        EzwinImageUUID uuid = input->uuids[i];
        BOOL visible = NO;
        for (size_t j = 0; j < result.imageCount; j++) if (retained[j] == uuid.header) { visible = YES; break; }
        if (!visible) continue;
        if (executable && uuid.header == executable) uuid.header = decoy;
        result.uuids[result.uuidCount++] = uuid;
    }
    uint32_t count = (uint32_t)result.imageCount;
    uint64_t images = (uint64_t)result.images, uuids = (uint64_t)result.uuids;
    memcpy(result.prefix + 4, &count, 4);
    memcpy(result.prefix + 8, &images, 8);
    if (input->uuidCount) { memcpy(result.prefix + 88, &result.uuidCount, 8); memcpy(result.prefix + 96, &uuids, 8); }
    *output = result;
}
int hook_task_info(uint64_t task, uint32_t flavor, EzwinTaskInfo *output, BOOL (*isExecutable)(uint64_t)) {
    ORIG(task_info);
    int result = orig_task_info(task, flavor, output);
    if (result == 0 && flavor == 17 && output->imageCount) {
        EzwinTaskInfo filtered = {};
        Ezwin_FilterTaskInfo(output, &filtered, gDecoyHeader, isExecutable);
        Ezwin_FreeTaskInfo(output);
        *output = filtered;
    }
    return result;
}
NSString *hook_signing_identifier(uint64_t task, uint64_t error) {
    ORIG(signing_identifier);
    NSString *prefix = @"com.criticalforceentertainment.criticalops";
    NSString *original = orig_signing_identifier(task, error);
    if ([original hasPrefix:prefix]) return prefix;
    return orig_signing_identifier(task, error);
}

uint64_t Ezwin_GetPC(const EzwinThreadState *state) {
    uint64_t pc; memcpy(&pc, state->bytes + 0x100, 8); return pc;
}
void Ezwin_SetPC(EzwinThreadState *state, uint64_t pc) { memcpy(state->bytes + 0x100, &pc, 8); }
int Ezwin_HandleBreakpoint(const EzwinRedirect *hooks, size_t count,
    const EzwinThreadState *oldState, uint32_t oldCount,
    EzwinThreadState *newState, uint32_t *newCount) {
    for (size_t i = 0; i < count; i++) {
        if (hooks[i].target != Ezwin_GetPC(oldState)) continue;
        memcpy(newState, oldState, sizeof(*newState));
        Ezwin_SetPC(newState, hooks[i].replacement);
        *newCount = oldCount;
        return 0;
    }
    return 5;
}
