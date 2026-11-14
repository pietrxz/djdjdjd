#pragma once
#import <Foundation/Foundation.h>
#include <stdint.h>
#include <stdio.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/types.h>

// All addresses are RVAs within the analyzed file.
typedef struct { const char *className; uint64_t entry; } EzwinLoadEntry;
typedef struct {
    uint64_t loadEntry;
    const char *className, *selector, *encoding;
    uint64_t implementation;
    BOOL metaclass;
} EzwinMethodEntry;
typedef struct {
    const char *className, *selector;
    uint64_t replacement, originalSlot, callsite, helper;
    BOOL classMethod;
} EzwinObjcHook;
typedef struct { const char *name; uint64_t replacement, originalSlot; } EzwinSymbolHook;
typedef struct { const char *name; uint64_t target, replacement; } EzwinBreakpointHook;
typedef struct { uint64_t slot, expectedOriginal, replacement, originalSlot; } EzwinPointerHook;

extern const EzwinLoadEntry kEzwinLoads[];
extern const EzwinMethodEntry kEzwinMethods[];
extern const EzwinObjcHook kEzwinObjcHooks[];
extern const EzwinSymbolHook kEzwinSymbolHooks[];
extern const EzwinBreakpointHook kEzwinBreakpointHooks[];
extern const EzwinPointerHook kEzwinPointerHooks[];
extern const size_t kEzwinLoadCount, kEzwinMethodCount, kEzwinObjcHookCount;
extern const size_t kEzwinSymbolHookCount, kEzwinBreakpointCount, kEzwinPointerHookCount;
extern const char *kEzwinSHA256, *kUnitySHA256;

BOOL Ezwin_IsExactHiddenPath(const char *path);
BOOL Ezwin_IsVisiblePath(const char *path);
uint64_t Ezwin_PathHash(const char *path);
uint64_t Ezwin_Address(uint64_t base, uint64_t rva);
NSInteger Ezwin_ScanPattern(const uint8_t *data, size_t size, const char *pattern);

// image: bytes, base, fileType, segments, imports, pointers.
NSMutableDictionary *Ezwin_LoadMachO(NSString *path, uint64_t base,
    uint64_t (*resolve)(const char *name, void *context), void *context);
uint64_t Ezwin_ReadPointer(NSMutableDictionary *image, uint64_t slot);
void Ezwin_WritePointer(NSMutableDictionary *image, uint64_t slot, uint64_t value);
NSInteger Ezwin_ScanUnityText(NSMutableDictionary *image, const char *pattern);

typedef struct {
    const char *filename;
    uint64_t base;
    const char *symbolName;
    uint64_t symbolAddress;
} EzwinDlInfo;
typedef struct { uint64_t header; const char *path; uint64_t modificationTime; } EzwinImageInfo;
typedef struct { uint64_t header; uint8_t uuid[16]; } EzwinImageUUID;
typedef struct {
    uint8_t prefix[160];
    EzwinImageInfo *images;
    size_t imageCount;
    EzwinImageUUID *uuids;
    size_t uuidCount;
    BOOL ownsBuffers;
} EzwinTaskInfo;

// Inspection interface. The task_info and signing callbacks do not use the native Mach/CF ABI.
typedef struct {
    int (*fclose)(FILE *);
    int (*unlink)(const char *);
    int (*lstat)(const char *, struct stat *);
    int (*stat)(const char *, struct stat *);
    struct dirent *(*readdir)(DIR *);
    int (*truncate)(const char *, off_t);
    FILE *(*fopen)(const char *, const char *);
    int (*access)(const char *, int);
    int (*open)(const char *, int);
    DIR *(*opendir)(const char *);
    uint64_t (*dlopen)(const char *, int);
    uint64_t (*dlsym)(uint64_t, const char *);
    int (*dladdr)(uint64_t, EzwinDlInfo *);
    int (*taskInfo)(uint64_t, uint32_t, EzwinTaskInfo *);
    NSString *(*signingIdentifier)(uint64_t, uint64_t);
} EzwinOriginals;

void Ezwin_ConfigureHooks(EzwinOriginals originals, NSArray *images, uint64_t ezwinBase);
NSArray *Ezwin_GetVisibleImages(void);
int hook_fclose(FILE *stream);
int hook_unlink(const char *path);
int hook_lstat(const char *path, struct stat *output);
int hook_stat(const char *path, struct stat *output);
struct dirent *hook_readdir(DIR *directory);
int hook_truncate(const char *path, off_t length);
FILE *hook_fopen(const char *path, const char *mode);
int hook_access(const char *path, int mode);
DIR *hook_opendir(const char *path);
int hook_open(const char *path, int flags);
uint64_t hook_dlopen(const char *path, int mode);
uint64_t hook_dlsym(uint64_t handle, const char *name);
int hook_dladdr(uint64_t address, EzwinDlInfo *output);
int hook_task_info(uint64_t task, uint32_t flavor, EzwinTaskInfo *output, BOOL (*isExecutable)(uint64_t));
NSString *hook_signing_identifier(uint64_t task, uint64_t error);
uint32_t hook_dyld_image_count(void);
const char *hook_dyld_get_image_name(uint32_t index);
uint64_t hook_dyld_get_image_header(uint32_t index);
uint64_t hook_dyld_get_image_vmaddr_slide(uint32_t index);
void Ezwin_FilterTaskInfo(const EzwinTaskInfo *input, EzwinTaskInfo *output,
    uint64_t decoy, BOOL (*isExecutable)(uint64_t));
void Ezwin_FreeTaskInfo(EzwinTaskInfo *info);

typedef struct { uint64_t target, replacement; } EzwinRedirect;
typedef struct { uint8_t bytes[0x110]; } EzwinThreadState;
typedef struct {
    uint64_t bvr[16], bcr[16], wvr[16], wcr[16], mdscr;
} EzwinDebugState;
uint64_t Ezwin_GetPC(const EzwinThreadState *state);
void Ezwin_SetPC(EzwinThreadState *state, uint64_t pc);
int Ezwin_HandleBreakpoint(const EzwinRedirect *hooks, size_t hookCount,
    const EzwinThreadState *oldState, uint32_t oldCount,
    EzwinThreadState *newState, uint32_t *newCount);

typedef struct {
    void *context;
    uint64_t (*findClass)(void *, const char *, BOOL);
    uint64_t (*findMethod)(void *, uint64_t, const char *);
    const char *(*typeEncoding)(void *, uint64_t);
    void (*prepareBridge)(void *, uint64_t, const char *, uint64_t);
    uint64_t (*replaceMethod)(void *, uint64_t, const char *, uint64_t, const char *);
    uint64_t (*implementation)(void *, uint64_t method);
    uint64_t (*replacementBody)(void *, const EzwinObjcHook *hook);
} EzwinObjcAPI;
typedef struct {
    void *context;
    uint32_t (*capacity)(void *);
    void (*configureService)(void *, uint32_t, uint32_t, uint32_t, uint64_t, uint64_t);
    void (*setDebugState)(void *, const EzwinDebugState *);
} EzwinMachAPI;
typedef void (^EzwinImageCallback)(NSMutableDictionary *image);

size_t Ezwin_RegisterLoadMethods(EzwinObjcAPI api, uint64_t base);
BOOL Ezwin_InstallObjcHook(EzwinObjcAPI api, const EzwinObjcHook *hook,
    uint64_t base, NSMutableDictionary *originals);
NSDictionary *Ezwin_InstallNativeObjcHooks(void);
BOOL Ezwin_ReplaceObjcMethod(Class target, SEL selector, IMP replacement, IMP *original);
size_t Ezwin_RebindImage(NSMutableDictionary *image, uint64_t base, NSMutableDictionary *originals);
NSMutableDictionary *Ezwin_RegisterImageCallback(uint64_t base, void (^registerCallback)(EzwinImageCallback));
void Ezwin_ReplaceUnityPointer(NSMutableDictionary *image, const EzwinPointerHook *hook,
    uint64_t base, NSMutableDictionary *originals);
NSMutableDictionary *Ezwin_RunStartup(NSMutableDictionary *unity, uint64_t base,
    EzwinObjcAPI objc, EzwinMachAPI mach, NSArray *processImages);
