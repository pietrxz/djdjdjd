#include "hooks/EzwinImportRebinder.h"
#include <mach-o/nlist.h>
#include <mach/mach.h>
#include <string.h>

static bool range(uint64_t start,uint64_t size,uint64_t low,uint64_t length) {
    return start>=low && size<=length && start-low<=length-size;
}
static bool writeSlot(uintptr_t *slot,uintptr_t value,EzwinRebindResult *result) {
    vm_address_t address=(vm_address_t)slot;vm_size_t size=0;
    vm_region_basic_info_data_64_t info={};mach_msg_type_number_t count=VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object=MACH_PORT_NULL;
    kern_return_t error=vm_region_64(mach_task_self(),&address,&size,VM_REGION_BASIC_INFO_64,
        (vm_region_info_t)&info,&count,&object);
    if(object)mach_port_deallocate(mach_task_self(),object);
    if(error!=KERN_SUCCESS || !range((uintptr_t)slot,8,address,size)) {
        ++result->protectionFailures;return false;
    }
    bool writable=(info.protection&VM_PROT_WRITE)!=0;
    vm_address_t page=(uintptr_t)slot&~((uintptr_t)vm_page_size-1);
    if(!writable && vm_protect(mach_task_self(),page,vm_page_size,false,
        info.protection|VM_PROT_WRITE|VM_PROT_COPY)!=KERN_SUCCESS) {
        ++result->protectionFailures;return false;
    }
    __atomic_store_n(slot,value,__ATOMIC_RELEASE);
    if(!writable && vm_protect(mach_task_self(),page,vm_page_size,false,info.protection)!=KERN_SUCCESS)
        ++result->restoreFailures;
    return true;
}
EzwinRebindResult EzwinRebindImports(const mach_header_64 *image,intptr_t slide,
    EzwinImportBinding *bindings,size_t count) {
    EzwinRebindResult result={};
    if(!image || image->magic!=MH_MAGIC_64 || !bindings || !count || image->sizeofcmds>0x400000 ||
        image->ncmds>65536)return result;
    const symtab_command *symbols=nullptr;const dysymtab_command *dynamic=nullptr;
    const segment_command_64 *linkedit=nullptr;
    const uint8_t *begin=(const uint8_t *)(image+1),*end=begin+image->sizeofcmds,*cursor=begin;
    for(unsigned i=0;i<image->ncmds;++i) {
        if((size_t)(end-cursor)<sizeof(load_command))return result;
        const load_command *command=(const load_command *)cursor;
        if(command->cmdsize<8 || command->cmdsize>(size_t)(end-cursor))return result;
        if(command->cmd==LC_SYMTAB && command->cmdsize>=sizeof(symtab_command))symbols=(const symtab_command *)cursor;
        if(command->cmd==LC_DYSYMTAB && command->cmdsize>=sizeof(dysymtab_command))dynamic=(const dysymtab_command *)cursor;
        if(command->cmd==LC_SEGMENT_64 && command->cmdsize>=sizeof(segment_command_64)) {
            const segment_command_64 *segment=(const segment_command_64 *)cursor;
            if(!strncmp(segment->segname,"__LINKEDIT",16))linkedit=segment;
        }
        cursor+=command->cmdsize;
    }
    if(!symbols || !dynamic || !linkedit ||
        !range(symbols->symoff,(uint64_t)symbols->nsyms*sizeof(nlist_64),linkedit->fileoff,linkedit->filesize) ||
        !range(symbols->stroff,symbols->strsize,linkedit->fileoff,linkedit->filesize) ||
        !range(dynamic->indirectsymoff,(uint64_t)dynamic->nindirectsyms*4,linkedit->fileoff,linkedit->filesize))return result;
    uintptr_t base=(uintptr_t)(slide+linkedit->vmaddr-linkedit->fileoff);
    const nlist_64 *names=(const nlist_64 *)(base+symbols->symoff);
    const char *strings=(const char *)(base+symbols->stroff);
    const uint32_t *indices=(const uint32_t *)(base+dynamic->indirectsymoff);
    cursor=begin;
    for(unsigned i=0;i<image->ncmds;++i) {
        const load_command *command=(const load_command *)cursor;
        if(command->cmd==LC_SEGMENT_64 && command->cmdsize>=sizeof(segment_command_64)) {
            const segment_command_64 *segment=(const segment_command_64 *)cursor;
            if(segment->nsects>(command->cmdsize-sizeof(*segment))/sizeof(section_64))return result;
            const section_64 *sections=(const section_64 *)(segment+1);
            for(unsigned j=0;j<segment->nsects;++j) {
                const section_64 *section=sections+j;
                unsigned type=section->flags&SECTION_TYPE;
                if(type!=S_LAZY_SYMBOL_POINTERS && type!=S_NON_LAZY_SYMBOL_POINTERS)continue;
                uint64_t slots=section->size/sizeof(uintptr_t);
                if(slots>0x100000 || section->addr%8 || section->size%8 || !range(section->addr,section->size,segment->vmaddr,segment->vmsize) ||
                    section->reserved1>dynamic->nindirectsyms || slots>dynamic->nindirectsyms-section->reserved1)continue;
                uintptr_t *pointers=(uintptr_t *)(slide+section->addr);
                for(uint64_t k=0;k<slots;++k) {
                    uint32_t index=indices[section->reserved1+k];
                    if(index&(INDIRECT_SYMBOL_LOCAL|INDIRECT_SYMBOL_ABS) || index>=symbols->nsyms)continue;
                    uint32_t offset=names[index].n_un.n_strx;
                    if(offset>=symbols->strsize || !memchr(strings+offset,0,symbols->strsize-offset))continue;
                    const char *name=strings+offset;if(*name=='_')++name;
                    for(size_t b=0;b<count;++b) {
                        if(!bindings[b].replacement || strcmp(name,bindings[b].name))continue;
                        if(__atomic_load_n(pointers+k,__ATOMIC_ACQUIRE)!=bindings[b].replacement &&
                            writeSlot(pointers+k,bindings[b].replacement,&result)) {
                            ++bindings[b].writes;++result.writes;
                        }
                        break;
                    }
                }
            }
        }
        cursor+=command->cmdsize;
    }
    return result;
}
