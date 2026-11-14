#include "hooks/EzwinStaticInline.h"
#include <mach-o/loader.h>
#include <mach-o/dyld.h>
#include <string.h>

static StaticInlineHookBlock *findBlock(uintptr_t base, uintptr_t target) {
    if (!base || target & 3) return nullptr;
    const mach_header_64 *header = (const mach_header_64 *)base;
    if (header->magic != MH_MAGIC_64 || header->sizeofcmds > 0x10000) return nullptr;
    const uint8_t *end = (const uint8_t *)(header + 1) + header->sizeofcmds;
    const load_command *command = (const load_command *)(header + 1);
    const segment_command_64 *text = nullptr, *data = nullptr;
    bool executableTarget = false;
    uint64_t headerAddress = UINT64_MAX;
    for (uint32_t i = 0; i < header->ncmds; ++i) {
        if ((const uint8_t *)(command + 1) > end || command->cmdsize < sizeof(*command) ||
            (const uint8_t *)command + command->cmdsize > end) return nullptr;
        if (command->cmd == LC_SEGMENT_64 && command->cmdsize >= sizeof(segment_command_64)) {
            const segment_command_64 *segment = (const segment_command_64 *)command;
            if (!segment->fileoff && segment->filesize) headerAddress = segment->vmaddr;
            if ((segment->initprot & VM_PROT_EXECUTE) && segment->vmaddr <= target &&
                target - segment->vmaddr < segment->vmsize && strncmp(segment->segname, "__HOOK_TEXT", 16)) executableTarget = true;
            if (!strncmp(segment->segname, "__HOOK_TEXT", 16)) text = segment;
            if (!strncmp(segment->segname, "__HOOK_DATA", 16)) data = segment;
        }
        command = (const load_command *)((const uint8_t *)command + command->cmdsize);
    }
    if (!text || !data || !executableTarget || headerAddress == UINT64_MAX || data->vmsize > 0x10000 ||
        data->vmaddr < headerAddress || text->vmaddr < headerAddress ||
        !(data->initprot & VM_PROT_WRITE) || !(text->initprot & VM_PROT_EXECUTE)) return nullptr;
    uintptr_t textStart = text->vmaddr - headerAddress, textEnd = textStart + text->vmsize;
    StaticInlineHookBlock *blocks = (StaticInlineHookBlock *)(base + data->vmaddr - headerAddress);
    for (size_t i = 0; i < data->vmsize / sizeof(*blocks); ++i) {
        StaticInlineHookBlock *block = blocks + i;
        if (block->hook_vaddr != target) continue;
        if (!block->hook_size || block->hook_size > 64 || block->hook_size & 3 ||
            block->original_vaddr < textStart || block->original_vaddr >= textEnd ||
            block->code_vaddr < textStart || block->code_vaddr >= textEnd ||
            block->code_size > textEnd - block->code_vaddr) return nullptr;
        return block;
    }
    return nullptr;
}

uintptr_t EzwinStaticOriginal(uintptr_t base, uintptr_t target) {
    StaticInlineHookBlock *block = findBlock(base, target);
    return block ? base + block->original_vaddr : 0;
}
uintptr_t EzwinStaticReplacementSlot(uintptr_t base, uintptr_t target) {
    StaticInlineHookBlock *block=findBlock(base,target);
    return block?(uintptr_t)&block->target_replace:0;
}
bool EzwinValidateStaticRoutes(uintptr_t base, const EzwinStaticRoute *routes, size_t count) {
    if (!routes || !count || count > 32) return false;
    for (size_t i = 0; i < count; ++i) {
        StaticInlineHookBlock *block = findBlock(base, routes[i].target);
        if (!block || !routes[i].replacement || (block->target_replace &&
            (uintptr_t)block->target_replace != routes[i].replacement)) return false;
        for (size_t j = 0; j < i; ++j) if (routes[j].target == routes[i].target) return false;
    }
    return true;
}
bool EzwinActivateStaticRoutes(uintptr_t base, const EzwinStaticRoute *routes, size_t count) {
    if (!EzwinValidateStaticRoutes(base, routes, count)) return false;
    for (size_t i = 0; i < count; ++i) {
        StaticInlineHookBlock *block = findBlock(base, routes[i].target);
        __atomic_store_n(&block->target_replace, (void *)routes[i].replacement, __ATOMIC_RELEASE);
    }
    return true;
}
void *StaticInlineHookFunction(const char *machoPath, uint64_t address, void *replacement) {
    if (!machoPath || !replacement) return nullptr;
    size_t length = strlen(machoPath);
    for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
        const char *path = _dyld_get_image_name(i);
        size_t size = path ? strlen(path) : 0;
        if (size < length || strcmp(path + size - length, machoPath)) continue;
        uintptr_t base = (uintptr_t)_dyld_get_image_header(i);
        EzwinStaticRoute route = {(uintptr_t)address, (uintptr_t)replacement};
        uintptr_t original = EzwinStaticOriginal(base, address);
        return original && EzwinActivateStaticRoutes(base, &route, 1) ? (void *)original : nullptr;
    }
    return nullptr;
}
