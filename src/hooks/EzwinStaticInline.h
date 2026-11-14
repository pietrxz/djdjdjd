#pragma once
#include <stdint.h>
#include <stddef.h>

// Binary-compatible with CopsMainNew/CoreEngine.mm and dobby_defines.h.
struct StaticInlineHookBlock {
    uint64_t hook_vaddr, hook_size, code_vaddr, code_size;
    uint64_t patched_vaddr, original_vaddr, instrument_vaddr;
    uint64_t patch_size, patch_hash;
    void *target_replace, *instrument_handler;
};
static_assert(sizeof(StaticInlineHookBlock) == 88, "StaticInlineHook block ABI");

struct EzwinStaticRoute { uintptr_t target, replacement; };
uintptr_t EzwinStaticOriginal(uintptr_t base, uintptr_t target);
uintptr_t EzwinStaticReplacementSlot(uintptr_t base, uintptr_t target);
bool EzwinValidateStaticRoutes(uintptr_t base, const EzwinStaticRoute *routes, size_t count);
bool EzwinActivateStaticRoutes(uintptr_t base, const EzwinStaticRoute *routes, size_t count);
void *StaticInlineHookFunction(const char *machoPath, uint64_t address, void *replacement);
