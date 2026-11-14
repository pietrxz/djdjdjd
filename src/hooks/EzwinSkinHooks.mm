#include "unity/EzwinOffsets1900.h"
#include "hooks/EzwinSkinHooks.h"
#include "hooks/EzwinHardwareHooks.h"
#include <string.h>

extern "C" { uintptr_t EzwinWeaponResume, EzwinGloveResume; }

#if defined(__arm64__)
// The hardware breakpoint replaces the first SUB SP. Replay it before entering the original body at +4.
__attribute__((naked, noinline)) static uintptr_t weaponOriginal(uintptr_t, uintptr_t, uintptr_t, int, uint32_t, uintptr_t) {
    __asm__ volatile("sub sp, sp, #0x70\nadrp x16, _EzwinWeaponResume@PAGE\nldr x16, [x16, _EzwinWeaponResume@PAGEOFF]\nbr x16");
}
__attribute__((naked, noinline)) static uintptr_t gloveOriginal(uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t) {
    __asm__ volatile("sub sp, sp, #0x90\nadrp x16, _EzwinGloveResume@PAGE\nldr x16, [x16, _EzwinGloveResume@PAGEOFF]\nbr x16");
}
#endif

bool EzwinPrepareSkinContinuations(uintptr_t base) {
    if (!base) return false;
    uint32_t weapon, glove;
    memcpy(&weapon, (void *)(base + EzwinUF_WeaponSkin), 4); memcpy(&glove, (void *)(base + EzwinUF_GloveSkin), 4);
    if (weapon != 0xd101c3ff || glove != 0xd10243ff) return false;
    EzwinWeaponResume = base + EzwinResume_WeaponSkin; EzwinGloveResume = base + EzwinResume_GloveSkin;
    return true;
}
EzwinWeaponSkinOriginal EzwinOriginalWeaponSkin(void) {
#if defined(__arm64__)
    return weaponOriginal;
#else
    return nullptr;
#endif
}
EzwinGloveOriginal EzwinOriginalGloveSkin(void) {
#if defined(__arm64__)
    return gloveOriginal;
#else
    return nullptr;
#endif
}
kern_return_t EzwinInstallSkinHooks(uintptr_t base, uintptr_t weapon, uintptr_t glove) {
    if (!weapon || !glove || !EzwinPrepareSkinContinuations(base)) return KERN_INVALID_ARGUMENT;
    const EzwinHardwareRoute routes[] = {{base + EzwinUF_WeaponSkin, weapon}, {base + EzwinUF_GloveSkin, glove}};
    return EzwinInstallHardwareRoutes(routes, 2);
}
