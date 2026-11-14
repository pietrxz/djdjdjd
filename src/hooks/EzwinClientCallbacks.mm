#include "hooks/EzwinClientCallbacks.h"
#include "unity/EzwinOffsets1900.h"
#include "core/EzwinDiagnostics.h"
#include "hooks/EzwinStaticInline.h"
#include <mach/mach.h>
#include <pthread.h>
#include <mach-o/loader.h>
#include <string.h>

static EzwinClientFrameOriginal originalFrame;
static EzwinClientBeginOriginal originalBegin;
static EzwinClientIteratorOriginal originalYield,originalRequest;
static pthread_mutex_t installationMutex=PTHREAD_MUTEX_INITIALIZER;
static uintptr_t installedBase;
static unsigned installedCount,protectionFailures,restoreFailures,rollbackFailures;
static unsigned suspendFailures,resumeFailures;
static kern_return_t lastSuspendError;
static bool callbacksActive;
static uint64_t frameCalls,beginCalls,yieldCalls,requestCalls,yields,scopedYields;
static int lastReport,lastPhase,lastIteratorState;
static NSString *installationStage=@"Waiting for the matching Unity image";
struct RequestScope { uintptr_t iterator,owner; RequestScope *previous; };
static thread_local RequestScope *requestScope;
static bool threadFault(unsigned stage);

static bool readMemory(uintptr_t address,void *output,vm_size_t size) {
    if(address<0x10000)return false;
    vm_size_t copied=0;
    return vm_read_overwrite(mach_task_self(),address,size,(vm_address_t)output,&copied)==KERN_SUCCESS && copied==size;
}
static void frame(uintptr_t object,uintptr_t method) {
    if(!__atomic_load_n(&callbacksActive,__ATOMIC_ACQUIRE)) {
        __atomic_load_n(&originalFrame,__ATOMIC_ACQUIRE)(object,method);return;
    }
    int value;
    if(readMemory(object+EzwinField_ClientReportCode,&value,sizeof(value)))
        __atomic_store_n(&lastReport,value,__ATOMIC_RELAXED);
    if(readMemory(object+EzwinField_ClientReportPhase,&value,sizeof(value)))
        __atomic_store_n(&lastPhase,value,__ATOMIC_RELAXED);
    __atomic_fetch_add(&frameCalls,1,__ATOMIC_RELAXED);
    EzwinTraceCheckpoint(64,"client: frame pointer callback entered");
    __atomic_load_n(&originalFrame,__ATOMIC_ACQUIRE)(object,method);
}
static void begin(uintptr_t object,uintptr_t method) {
    if(!__atomic_load_n(&callbacksActive,__ATOMIC_ACQUIRE)) {
        __atomic_load_n(&originalBegin,__ATOMIC_ACQUIRE)(object,method);return;
    }
    __atomic_fetch_add(&beginCalls,1,__ATOMIC_RELAXED);
    EzwinTraceCheckpoint(65,"client: begin pointer callback entered");
    __atomic_load_n(&originalBegin,__ATOMIC_ACQUIRE)(object,method);
}
static bool yieldIterator(uintptr_t object,uintptr_t method) {
    bool observe=__atomic_load_n(&callbacksActive,__ATOMIC_ACQUIRE);
    bool advanced=__atomic_load_n(&originalYield,__ATOMIC_ACQUIRE)(object,method);
    if(!observe)return advanced;
    __atomic_fetch_add(&yieldCalls,1,__ATOMIC_RELAXED);
    if(advanced && object) {
        int state;
        if(readMemory(object+EzwinField_IteratorState,&state,sizeof(state)))
            __atomic_store_n(&lastIteratorState,state,__ATOMIC_RELAXED);
        uintptr_t current=0;
        if(readMemory(object+EzwinField_IteratorCurrent,&current,sizeof(current))) {
            __atomic_fetch_add(&yields,1,__ATOMIC_RELAXED);
            if(requestScope)__atomic_fetch_add(&scopedYields,1,__ATOMIC_RELAXED);
        }
    }
    EzwinTraceCheckpoint(66,"client: yield iterator callback completed");
    return advanced;
}
static bool requestIterator(uintptr_t object,uintptr_t method) {
    if(!__atomic_load_n(&callbacksActive,__ATOMIC_ACQUIRE))
        return __atomic_load_n(&originalRequest,__ATOMIC_ACQUIRE)(object,method);
    RequestScope scope={object,0,requestScope};
    if(object)readMemory(object+EzwinField_RequestIteratorOwner,&scope.owner,sizeof(scope.owner));
    uintptr_t payload=0;
    if(scope.owner)readMemory(scope.owner+EzwinField_RequestIteratorPayload,&payload,sizeof(payload));
    struct ScopeGuard {
        RequestScope *previous;
        explicit ScopeGuard(RequestScope *scope):previous(requestScope) { requestScope=scope; }
        ~ScopeGuard() { requestScope=previous; }
    } guard(payload?&scope:requestScope);
    __atomic_fetch_add(&requestCalls,1,__ATOMIC_RELAXED);
    EzwinTraceCheckpoint(67,"client: request iterator callback entered");
    return __atomic_load_n(&originalRequest,__ATOMIC_ACQUIRE)(object,method);
}
struct ClientRoute { uintptr_t slot,original,replacement; };
static const ClientRoute routes[]={
    {EzwinSlot_ClientFrame,EzwinUF_ClientFrame,(uintptr_t)frame},
    {EzwinSlot_ClientBegin,EzwinUF_ClientBegin,(uintptr_t)begin},
    {EzwinSlot_ClientYieldIterator,EzwinUF_ClientYieldIterator,(uintptr_t)yieldIterator},
    {EzwinSlot_ClientRequestIterator,EzwinUF_ClientRequestIterator,(uintptr_t)requestIterator}
};
static bool replacePointer(uintptr_t address,uintptr_t expected,uintptr_t replacement) {
    vm_address_t region=address;vm_size_t size=0;vm_region_basic_info_data_64_t info={};
    mach_msg_type_number_t count=VM_REGION_BASIC_INFO_COUNT_64;mach_port_t object=0;
    kern_return_t error=vm_region_64(mach_task_self(),&region,&size,VM_REGION_BASIC_INFO_64,(vm_region_info_t)&info,&count,&object);
    if(object)mach_port_deallocate(mach_task_self(),object);
    if(error!=KERN_SUCCESS || size<sizeof(uintptr_t) || region>address || address-region>size-sizeof(uintptr_t)) {
        ++protectionFailures;return false;
    }
    bool writable=info.protection&VM_PROT_WRITE;vm_address_t page=address&~((uintptr_t)vm_page_size-1);
    if(!writable && vm_protect(mach_task_self(),page,vm_page_size,false,info.protection|VM_PROT_WRITE|VM_PROT_COPY)!=KERN_SUCCESS) {
        ++protectionFailures;return false;
    }
    bool changed=__atomic_compare_exchange_n((uintptr_t *)address,&expected,replacement,false,__ATOMIC_RELEASE,__ATOMIC_RELAXED);
    if(!writable && (threadFault(4)||vm_protect(mach_task_self(),page,vm_page_size,false,info.protection)!=KERN_SUCCESS))++restoreFailures;
    return changed;
}
#ifdef EZWIN_HOOK_TESTING
static bool (*testWriter)(uintptr_t,uintptr_t,uintptr_t);
#endif
static bool write(uintptr_t address,uintptr_t expected,uintptr_t replacement) {
#ifdef EZWIN_HOOK_TESTING
    if(testWriter)return testWriter(address,expected,replacement);
#endif
    return replacePointer(address,expected,replacement);
}
static bool matchingImage(uintptr_t base) {
    mach_header_64 header={};
    if(base>UINTPTR_MAX-EzwinSlot_ClientRequestIterator || !readMemory(base,&header,sizeof(header)) ||
        header.magic!=MH_MAGIC_64 || header.cputype!=CPU_TYPE_ARM64 || header.ncmds>4096 || header.sizeofcmds>1024*1024)return false;
    uintptr_t cursor=base+sizeof(header),end=cursor+header.sizeofcmds;
    for(uint32_t i=0;i<header.ncmds;++i) {
        load_command command={};
        if(end-cursor<sizeof(command)||!readMemory(cursor,&command,sizeof(command)) ||
            command.cmdsize<sizeof(command)||command.cmdsize>end-cursor)return false;
        if(command.cmd==LC_UUID) {
            uuid_command uuid={};
            return command.cmdsize==sizeof(uuid)&&readMemory(cursor,&uuid,sizeof(uuid))&&!memcmp(uuid.uuid,EzwinUnityUUID,16);
        }
        cursor+=command.cmdsize;
    }
    return false;
}
#ifdef EZWIN_HOOK_TESTING
static unsigned faultStage,faultOrdinal,faultSeen;
static bool threadFault(unsigned stage) {
    return stage==faultStage && ++faultSeen==faultOrdinal;
}
#else
static bool threadFault(unsigned) { return false; }
#endif

// No Foundation, heap allocation, application locks or game calls are allowed
// between stop() and resume(): a stopped thread can own any of those locks.
// task_threads returns kernel-allocated VM, and all storage below is fixed-size.
class PeerThreads {
    thread_t held[1024]={};
    unsigned used=0;
    thread_t self=MACH_PORT_NULL;
public:
    bool stop() {
        self=mach_thread_self();
        for(unsigned pass=0;pass<8;++pass) {
            thread_act_array_t list=nullptr;mach_msg_type_number_t count=0;
            kern_return_t error=threadFault(1)?KERN_FAILURE:task_threads(mach_task_self(),&list,&count);
            if(error!=KERN_SUCCESS) { ++suspendFailures;lastSuspendError=error;return false; }
            bool valid=true,added=false;
            for(unsigned i=0;i<count;++i) {
                thread_t peer=list[i];bool known=peer==self;
                for(unsigned n=0;n<used&&!known;++n)known=held[n]==peer;
                if(valid&&!known) {
                    if(used==1024) { valid=false;++suspendFailures; }
                    else {
                        error=threadFault(2)?KERN_FAILURE:thread_suspend(peer);
                        if(error==KERN_SUCCESS) { held[used++]=peer;added=true;continue; }
                        // task_threads supplied a valid own-task control right;
                        // INVALID_ARGUMENT here also occurs when that peer dies
                        // during port-to-thread conversion before suspension.
                        if(error!=KERN_TERMINATED && error!=MACH_SEND_INVALID_DEST && error!=KERN_INVALID_ARGUMENT) { valid=false;++suspendFailures;lastSuspendError=error; }
                    }
                }
                mach_port_deallocate(mach_task_self(),peer);
            }
            vm_deallocate(mach_task_self(),(vm_address_t)list,count*sizeof(*list));
            if(!valid)return false;
            // A second enumeration also catches threads created during the
            // first suspension pass. No peer may still be running at commit.
            if(!added)return true;
        }
        ++suspendFailures;return false;
    }
    bool resume() {
        bool valid=true;
        while(used) {
            thread_t peer=held[--used];kern_return_t error=KERN_FAILURE;
            for(unsigned retry=0;retry<3;++retry) {
                error=threadFault(3)?KERN_FAILURE:thread_resume(peer);
                if(error==KERN_SUCCESS||error==KERN_TERMINATED||error==MACH_SEND_INVALID_DEST||error==KERN_INVALID_ARGUMENT)break;
                ++resumeFailures;
            }
            if(error!=KERN_SUCCESS&&error!=KERN_TERMINATED&&error!=MACH_SEND_INVALID_DEST&&error!=KERN_INVALID_ARGUMENT)valid=false;
            mach_port_deallocate(mach_task_self(),peer);
        }
        if(self) { mach_port_deallocate(mach_task_self(),self);self=MACH_PORT_NULL; }
        return valid;
    }
    ~PeerThreads() { resume(); }
};
struct CallbackPage {
    vm_address_t address;vm_prot_t protection;
};
static bool capturePages(uintptr_t base,const ClientRoute (&activation)[4],CallbackPage (&pages)[4],unsigned &used) {
    for(const ClientRoute &route:activation) {
        vm_address_t page=(base+route.slot)&~((uintptr_t)vm_page_size-1);
        bool known=false;for(unsigned n=0;n<used;++n)if(pages[n].address==page)known=true;
        if(known)continue;
        vm_address_t region=page;vm_size_t size=0;vm_region_basic_info_data_64_t info={};
        mach_msg_type_number_t count=VM_REGION_BASIC_INFO_COUNT_64;mach_port_t object=0;
        kern_return_t error=vm_region_64(mach_task_self(),&region,&size,VM_REGION_BASIC_INFO_64,(vm_region_info_t)&info,&count,&object);
        if(object)mach_port_deallocate(mach_task_self(),object);
        if(error!=KERN_SUCCESS||region>page||page-region>=size) { ++protectionFailures;return false; }
        pages[used++]={page,info.protection};
    }
    return true;
}
static bool restorePages(const CallbackPage *pages,unsigned used) {
    bool valid=true;
    for(unsigned n=0;n<used;++n) {
        if(vm_protect(mach_task_self(),pages[n].address,vm_page_size,false,pages[n].protection)!=KERN_SUCCESS) {
            ++restoreFailures;valid=false;
        }
    }
    return valid;
}
bool EzwinInstallClientCallbacks(uintptr_t base) {
    if(!base)return false;
    pthread_mutex_lock(&installationMutex);
    bool success=false;
    do {
        if(installedBase && installedBase!=base) { installationStage=@"A different Unity image is already bound";break; }
        if(!matchingImage(base)) { installationStage=@"Unity UUID does not match the verified 1.90.0 image";break; }
        ClientRoute activation[4]={};bool prepared=true;
        for(unsigned i=0;i<4;++i) {
            uintptr_t slot=EzwinStaticReplacementSlot(base,routes[i].original);
            uintptr_t original=EzwinStaticOriginal(base,routes[i].original);
            if(!slot||!original) { prepared=false;break; }
            activation[i]={slot-base,original-base,routes[i].replacement};
        }
        if(!prepared) { installationStage=@"Four prepared 1.90.0 client static-inline blocks are required";break; }
        PeerThreads peers;
        if(!peers.stop()) {
            peers.resume();installationStage=@"Could not pause all peer threads; callback pointers unchanged";break;
        }
        // Everything until peers.resume() uses stack storage, atomics and
        // Mach calls only. Format diagnostics after all peers can run again.
        bool valid=true;
        uintptr_t unexpected=0;
        installedCount=0;
        for(unsigned i=0;i<4;++i) {
            const ClientRoute &route=activation[i];
            uintptr_t value=0;
            bool readable=readMemory(base+route.slot,&value,sizeof(value));
            if(readable && value==route.replacement)++installedCount;
            if(!readable ||
                (value!=0 && value!=route.replacement)) {
                if(valid)unexpected=route.slot;
                valid=false;
            }
            uintptr_t managed=0;
            if(!readMemory(base+routes[i].slot,&managed,sizeof(managed))||managed!=base+routes[i].original) {
                if(valid)unexpected=routes[i].slot;
                valid=false;
            }
        }
        installedBase=installedCount?base:0;
        if(!valid) {
            __atomic_store_n(&callbacksActive,false,__ATOMIC_RELEASE);
            peers.resume();
            installationStage=[NSString stringWithFormat:@"Unexpected callback pointer at Unity+0x%llx",(unsigned long long)unexpected];break;
        }
        if(installedCount==4) {
            __atomic_store_n(&callbacksActive,true,__ATOMIC_RELEASE);
            success=peers.resume();
            if(!success)__atomic_store_n(&callbacksActive,false,__ATOMIC_RELEASE);
            installationStage=success?@"Four current client static-inline routes installed":@"Peer thread resume failed";break;
        }
        __atomic_store_n(&callbacksActive,false,__ATOMIC_RELEASE);
        __atomic_store_n(&originalFrame,(EzwinClientFrameOriginal)(base+activation[0].original),__ATOMIC_RELEASE);
        __atomic_store_n(&originalBegin,(EzwinClientBeginOriginal)(base+activation[1].original),__ATOMIC_RELEASE);
        __atomic_store_n(&originalYield,(EzwinClientIteratorOriginal)(base+activation[2].original),__ATOMIC_RELEASE);
        __atomic_store_n(&originalRequest,(EzwinClientIteratorOriginal)(base+activation[3].original),__ATOMIC_RELEASE);
        CallbackPage pages[4]={};unsigned pageCount=0,restoreBefore=restoreFailures;
        valid=capturePages(base,activation,pages,pageCount);
        for(const ClientRoute &route:activation) {
            if(!valid)break;
            uintptr_t value=0;readMemory(base+route.slot,&value,sizeof(value));
            if(value==route.replacement)continue;
            if(!write(base+route.slot,0,route.replacement)) {
                valid=false;break;
            }
        }
        for(const ClientRoute &route:activation) {
            uintptr_t value=0;
            if(!readMemory(base+route.slot,&value,sizeof(value))||value!=route.replacement)valid=false;
        }
        if(restoreFailures!=restoreBefore)valid=false;
        if(!valid) {
            for(const ClientRoute &route:activation) {
                uintptr_t value=0;readMemory(base+route.slot,&value,sizeof(value));
                if(value==route.replacement && !write(base+route.slot,route.replacement,0))++rollbackFailures;
            }
        }
        bool permissionsRestored=restorePages(pages,pageCount);
        if(valid&&!permissionsRestored) {
            valid=false;
            for(const ClientRoute &route:activation) {
                uintptr_t value=0;readMemory(base+route.slot,&value,sizeof(value));
                if(value==route.replacement && !write(base+route.slot,route.replacement,0))++rollbackFailures;
            }
            restorePages(pages,pageCount);
        }
        installedCount=0;
        for(const ClientRoute &route:activation) {
            uintptr_t value=0;readMemory(base+route.slot,&value,sizeof(value));
            if(value==route.replacement)++installedCount;
        }
        installedBase=installedCount?base:0;
        success=valid && installedCount==4;
        // A residual callback after failed rollback remains pure passthrough.
        __atomic_store_n(&callbacksActive,success,__ATOMIC_RELEASE);
        bool resumed=peers.resume();
        if(!resumed)__atomic_store_n(&callbacksActive,false,__ATOMIC_RELEASE);
        success=success&&resumed;
        if(!resumed)installationStage=@"Peer thread resume failed";
        else if(success)installationStage=@"Four current client static-inline routes installed";
        else if(installedCount)installationStage=@"Callback pointer write failed; rollback incomplete, observers disabled, retry required";
        else installationStage=@"Callback pointer write failed; all entries restored";
    } while(false);
    pthread_mutex_unlock(&installationMutex);return success;
}
NSDictionary *EzwinClientCallbackStatus(void) {
    pthread_mutex_lock(&installationMutex);
    NSDictionary *status=@{@"installed":@(installedCount),@"planned":@4,@"complete":@(installedCount==4&&__atomic_load_n(&callbacksActive,__ATOMIC_ACQUIRE)),@"stage":installationStage,
        @"active":@(__atomic_load_n(&callbacksActive,__ATOMIC_ACQUIRE)),@"suspendFailures":@(suspendFailures),@"resumeFailures":@(resumeFailures),
        @"lastSuspendError":@(lastSuspendError),
        @"protectionFailures":@(protectionFailures),@"restoreFailures":@(restoreFailures),@"rollbackFailures":@(rollbackFailures),
        @"frameCalls":@(__atomic_load_n(&frameCalls,__ATOMIC_RELAXED)),@"beginCalls":@(__atomic_load_n(&beginCalls,__ATOMIC_RELAXED)),
        @"yieldCalls":@(__atomic_load_n(&yieldCalls,__ATOMIC_RELAXED)),@"requestCalls":@(__atomic_load_n(&requestCalls,__ATOMIC_RELAXED)),
        @"yields":@(__atomic_load_n(&yields,__ATOMIC_RELAXED)),@"scopedYields":@(__atomic_load_n(&scopedYields,__ATOMIC_RELAXED)),
        @"lastReport":@(__atomic_load_n(&lastReport,__ATOMIC_RELAXED)),@"lastPhase":@(__atomic_load_n(&lastPhase,__ATOMIC_RELAXED)),
        @"lastIteratorState":@(__atomic_load_n(&lastIteratorState,__ATOMIC_RELAXED)),
        @"backend":@"CoreEngine StaticInlineHook",@"metadataPointersModified":@NO,
        @"mode":@"Original trampolines and iterator results preserved; four static-inline entry routes"};
    pthread_mutex_unlock(&installationMutex);return status;
}
#ifdef EZWIN_HOOK_TESTING
extern "C" void EzwinTestClientOriginals(const uintptr_t *originals) {
    originalFrame=(EzwinClientFrameOriginal)originals[0];originalBegin=(EzwinClientBeginOriginal)originals[1];
    originalYield=(EzwinClientIteratorOriginal)originals[2];originalRequest=(EzwinClientIteratorOriginal)originals[3];
}
extern "C" void EzwinTestClientCopyOriginals(uintptr_t *output) {
    output[0]=(uintptr_t)__atomic_load_n(&originalFrame,__ATOMIC_ACQUIRE);
    output[1]=(uintptr_t)__atomic_load_n(&originalBegin,__ATOMIC_ACQUIRE);
    output[2]=(uintptr_t)__atomic_load_n(&originalYield,__ATOMIC_ACQUIRE);
    output[3]=(uintptr_t)__atomic_load_n(&originalRequest,__ATOMIC_ACQUIRE);
}
extern "C" void EzwinTestClientWriter(bool (*writer)(uintptr_t,uintptr_t,uintptr_t)) { testWriter=writer; }
extern "C" void EzwinTestClientThreadFault(unsigned stage,unsigned ordinal) { faultStage=stage;faultOrdinal=ordinal;faultSeen=0; }
extern "C" bool EzwinTestClientWritePointer(uintptr_t address,uintptr_t expected,uintptr_t replacement) {
    return replacePointer(address,expected,replacement);
}
#endif
