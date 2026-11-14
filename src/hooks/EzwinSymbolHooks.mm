#include "hooks/EzwinSymbolHooks.h"
#include "hooks/EzwinImportRebinder.h"
#include "legacy/EzwinHooks.h"
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <pthread.h>

// Only the main executable and UnityFramework import tables are changed.
// Calls made by this module keep their actual system implementations.
// Volatile pointers preserve the resolved implementations even in static-link tests.
static auto volatile system_stat = &stat;
static auto volatile system_lstat = &lstat;
static auto volatile system_access = &access;
static auto volatile system_truncate = &truncate;
static auto volatile system_fopen = &fopen;
static auto volatile system_opendir = &opendir;
static auto volatile system_open = &open;
static auto volatile system_readdir = &readdir;
static auto volatile system_dlopen = &dlopen;
static auto volatile system_dladdr = &dladdr;
static auto volatile system_dlsym = &dlsym;
static auto volatile system_task_info = &task_info;
static auto volatile system_fclose = &fclose;
static auto volatile system_unlink = &unlink;
static auto volatile system__dyld_image_count = &_dyld_image_count;
static auto volatile system__dyld_get_image_header = &_dyld_get_image_header;
static auto volatile system__dyld_get_image_name = &_dyld_get_image_name;
static auto volatile system__dyld_get_image_vmaddr_slide = &_dyld_get_image_vmaddr_slide;
typedef CFStringRef (*SigningIdentifier)(CFTypeRef,CFErrorRef *);
static SigningIdentifier signingIdentifier;

static CFStringRef filteredSigningIdentifier(CFTypeRef task,CFErrorRef *error) CF_RETURNS_RETAINED;
static CFStringRef filteredSigningIdentifier(CFTypeRef task,CFErrorRef *error) {
    SigningIdentifier original=__atomic_load_n(&signingIdentifier,__ATOMIC_ACQUIRE);
    if(!original) {
        original=(SigningIdentifier)system_dlsym(RTLD_DEFAULT,"SecTaskCopySigningIdentifier");
        if(original)__atomic_store_n(&signingIdentifier,original,__ATOMIC_RELEASE);
    }
    if(!original)return nullptr;
    CFStringRef value=original(task,error);
    CFStringRef identifier=CFSTR("com.criticalforceentertainment.criticalops");
    if(value && CFGetTypeID(value)==CFStringGetTypeID() && CFStringHasPrefix(value,identifier)) {
        CFRelease(value);return (CFStringRef)CFRetain(identifier);
    }
    return value;
}
static pthread_mutex_t symbolMutex=PTHREAD_MUTEX_INITIALIZER;
static bool registered;
static bool initializing;
static unsigned protectionFailures,restoreFailures,imageWrites;
struct ImageSnapshot {
    dyld_all_image_infos info;
    dyld_image_info images[1024];
    dyld_uuid_info uuids[1024];
    intptr_t slides[1024];
    uint32_t count;
};
static ImageSnapshot *snapshot;
static __thread ImageSnapshot *enumeration;

static bool visible(const char *path) {
    return Ezwin_IsVisiblePath(path) && (!path || !strstr(path,"libezwin-cracked"));
}
uint32_t EzwinFilterFileProbe(EzwinFileProbeOriginal original,const char *path) {
    // The verified Unity helper packs the carry/error flag into bit 31, rather than returning POSIX -1.
    if(!visible(path))return 0x80000002u;
    return original?original(path):0x80000002u;
}
static bool deny(const char *path) { if(visible(path))return false;errno=ENOENT;return true; }
static int forwardedFclose(FILE *stream) { return system_fclose(stream); }
static int forwardedUnlink(const char *path) { return system_unlink(path); }
static int filteredStat(const char *path,struct stat *value) { return deny(path)?-1:system_stat(path,value); }
static int filteredLstat(const char *path,struct stat *value) { return deny(path)?-1:system_lstat(path,value); }
static int filteredAccess(const char *path,int mode) { return deny(path)?-1:system_access(path,mode); }
static int filteredTruncate(const char *path,off_t size) { return deny(path)?-1:system_truncate(path,size); }
static FILE *filteredFopen(const char *path,const char *mode) { return deny(path)?nullptr:system_fopen(path,mode); }
static DIR *filteredOpendir(const char *path) { return deny(path)?nullptr:system_opendir(path); }
static int filteredOpen(const char *path,int flags,...) {
    mode_t mode=0;
    if(flags&O_CREAT) { va_list args;va_start(args,flags);mode=(mode_t)va_arg(args,int);va_end(args); }
    if(deny(path))return -1;
    return flags&O_CREAT?system_open(path,flags,mode):system_open(path,flags);
}
static dirent *filteredReaddir(DIR *directory) {
    dirent *entry;do { entry=system_readdir(directory); }while(entry && !visible(entry->d_name));return entry;
}
static void *filteredDlopen(const char *path,int mode) { return deny(path)?nullptr:system_dlopen(path,mode); }
static int filteredDladdr(const void *address,Dl_info *info) {
    int result=system_dladdr(address,info);
    if(result && info && !visible(info->dli_fname)) { memset(info,0,sizeof(*info));return 0; }
    return result;
}
static ImageSnapshot *current(void) { return __atomic_load_n(&snapshot,__ATOMIC_ACQUIRE); }
static uint32_t filteredImageCount(void) { enumeration=current();return enumeration?enumeration->count:0; }
static const mach_header *filteredImageHeader(uint32_t index) {
    ImageSnapshot *value=enumeration?enumeration:current();
    return value && index<value->count?value->images[index].imageLoadAddress:nullptr;
}
static const char *filteredImageName(uint32_t index) {
    ImageSnapshot *value=enumeration?enumeration:current();
    return value && index<value->count?value->images[index].imageFilePath:nullptr;
}
static intptr_t filteredImageSlide(uint32_t index) {
    ImageSnapshot *value=enumeration?enumeration:current();return value && index<value->count?value->slides[index]:0;
}
static kern_return_t filteredTaskInfo(task_name_t task,task_flavor_t flavor,task_info_t info,mach_msg_type_number_t *count) {
    kern_return_t result=system_task_info(task,flavor,info,count);
    ImageSnapshot *value=current();
    if(result==KERN_SUCCESS && task==mach_task_self() && flavor==TASK_DYLD_INFO && info && count &&
        *count>=TASK_DYLD_INFO_COUNT && value && value->info.version) {
        task_dyld_info_t dyld=(task_dyld_info_t)info;
        dyld->all_image_info_addr=(mach_vm_address_t)&value->info;
        dyld->all_image_info_size=sizeof(value->info);
    }
    return result;
}
static void *filteredDlsym(void *,const char *);
static EzwinImportBinding bindings[]={
    {"fclose",(uintptr_t)forwardedFclose,0},{"unlink",(uintptr_t)forwardedUnlink,0},
    {"lstat",(uintptr_t)filteredLstat,0},{"stat",(uintptr_t)filteredStat,0},
    {"readdir",(uintptr_t)filteredReaddir,0},{"truncate",(uintptr_t)filteredTruncate,0},
    {"fopen",(uintptr_t)filteredFopen,0},{"_dyld_image_count",(uintptr_t)filteredImageCount,0},
    {"_dyld_get_image_header",(uintptr_t)filteredImageHeader,0},{"_dyld_get_image_name",(uintptr_t)filteredImageName,0},
    {"_dyld_get_image_vmaddr_slide",(uintptr_t)filteredImageSlide,0},{"task_info",(uintptr_t)filteredTaskInfo,0},
    {"dlsym",(uintptr_t)filteredDlsym,0},{"dladdr",(uintptr_t)filteredDladdr,0},
    {"dlopen",(uintptr_t)filteredDlopen,0},{"access",(uintptr_t)filteredAccess,0},
    {"opendir",(uintptr_t)filteredOpendir,0},{"open",(uintptr_t)filteredOpen,0},
    {"SecTaskCopySigningIdentifier",(uintptr_t)filteredSigningIdentifier,0}
};
static const size_t bindingCount=sizeof(bindings)/sizeof(bindings[0]);
static void *filteredDlsym(void *handle,const char *name) {
    void *result=system_dlsym(handle,name);if(!result || !name)return result;
    for(size_t i=0;i<bindingCount;++i)if(!strcmp(name,bindings[i].name))return (void *)bindings[i].replacement;
    return result;
}
static void refreshImages(const mach_header *removed) {
    ImageSnapshot *value=(ImageSnapshot *)calloc(1,sizeof(ImageSnapshot));if(!value)return;
    task_dyld_info_data_t task={};mach_msg_type_number_t count=TASK_DYLD_INFO_COUNT;
    if(system_task_info(mach_task_self(),TASK_DYLD_INFO,(task_info_t)&task,&count)==KERN_SUCCESS) {
        vm_size_t copied=0;
        vm_read_overwrite(mach_task_self(),task.all_image_info_addr,
            task.all_image_info_size<sizeof(value->info)?task.all_image_info_size:sizeof(value->info),
            (mach_vm_address_t)&value->info,&copied);
    }
    uint32_t total=system__dyld_image_count();
    for(uint32_t i=0;i<total && value->count<1024;++i) {
        const mach_header *header=system__dyld_get_image_header(i);const char *path=system__dyld_get_image_name(i);
        if(!header || header==removed || !visible(path))continue;
        uint32_t n=value->count++;
        value->images[n]={header,path,0};value->slides[n]=system__dyld_get_image_vmaddr_slide(i);
        value->uuids[n].imageLoadAddress=header;
        const uint8_t *cursor=(const uint8_t *)header+(header->magic==MH_MAGIC_64?sizeof(mach_header_64):sizeof(mach_header));
        for(uint32_t command=0;command<header->ncmds;++command) {
            const load_command *load=(const load_command *)cursor;
            if(load->cmd==LC_UUID) { memcpy(value->uuids[n].imageUUID,((const uuid_command *)load)->uuid,16);break; }
            if(load->cmdsize<8)break;cursor+=load->cmdsize;
        }
    }
    value->info.infoArray=value->images;value->info.infoArrayCount=value->count;
    value->info.uuidArray=value->uuids;value->info.uuidArrayCount=value->count;
    value->info.initialImageCount=value->count;
    value->info.dyldAllImageInfosAddress=&value->info;
    // Published generations stay alive for clients holding task_info pointers.
    __atomic_store_n(&snapshot,value,__ATOMIC_RELEASE);
}
static void imageAdded(const mach_header *image,intptr_t slide) {
    pthread_mutex_lock(&symbolMutex);
    if(!initializing)refreshImages(nullptr);
    Dl_info info={};system_dladdr(image,&info);
    const char *name=info.dli_fname?strrchr(info.dli_fname,'/'):nullptr;name=name?name+1:info.dli_fname;
    if(image==system__dyld_get_image_header(0) || (name && !strcmp(name,"UnityFramework"))) {
        EzwinRebindResult result=EzwinRebindImports((const mach_header_64 *)image,slide,bindings,bindingCount);
        imageWrites+=result.writes;protectionFailures+=result.protectionFailures;restoreFailures+=result.restoreFailures;
    }
    pthread_mutex_unlock(&symbolMutex);
}
static void imageRemoved(const mach_header *image,intptr_t) {
    pthread_mutex_lock(&symbolMutex);refreshImages(image);pthread_mutex_unlock(&symbolMutex);
}
void EzwinInstallSymbolHooks(void) {
    @synchronized ([NSProcessInfo processInfo]) {
        if(registered)return;registered=true;
        SigningIdentifier original=(SigningIdentifier)system_dlsym(RTLD_DEFAULT,"SecTaskCopySigningIdentifier");
        if(original)__atomic_store_n(&signingIdentifier,original,__ATOMIC_RELEASE);
        pthread_mutex_lock(&symbolMutex);initializing=true;refreshImages(nullptr);pthread_mutex_unlock(&symbolMutex);
        _dyld_register_func_for_add_image(imageAdded);_dyld_register_func_for_remove_image(imageRemoved);
        pthread_mutex_lock(&symbolMutex);initializing=false;refreshImages(nullptr);pthread_mutex_unlock(&symbolMutex);
    }
}
NSDictionary *EzwinSymbolHookStatus(void) {
    pthread_mutex_lock(&symbolMutex);
    NSMutableArray *connected=[NSMutableArray array],*missing=[NSMutableArray array];
    for(size_t i=0;i<bindingCount;++i)[(bindings[i].writes?connected:missing) addObject:@(bindings[i].name)];
    NSDictionary *result=@{@"enabled":@(registered),@"connected":connected,@"missing":missing,
        @"writes":@(imageWrites),@"protectionFailures":@(protectionFailures),@"restoreFailures":@(restoreFailures),
        @"scope":@"main executable and UnityFramework imports",@"planned":@(bindingCount),
        @"signingIdentityHook":@YES,@"signingIdentityResolved":@(__atomic_load_n(&signingIdentifier,__ATOMIC_ACQUIRE)!=nullptr),
        @"signingIdentityViaDlsym":@(bindings[12].writes>0)};
    pthread_mutex_unlock(&symbolMutex);return result;
}

#ifdef EZWIN_HOOK_TESTING
extern "C" uintptr_t EzwinTestSymbol(const char *name) {
    for(size_t i=0;i<bindingCount;++i)if(!strcmp(name,bindings[i].name))return bindings[i].replacement;return 0;
}
extern "C" void EzwinTestRefreshImages(void) { refreshImages(nullptr); }
extern "C" void EzwinTestSigningOriginal(uintptr_t original) {
    __atomic_store_n(&signingIdentifier,(SigningIdentifier)original,__ATOMIC_RELEASE);
}
#endif
