#pragma once
#include "features/skins/EzwinSkinChanger.h"
#include <mach/mach.h>
bool EzwinPrepareSkinContinuations(uintptr_t base);
EzwinWeaponSkinOriginal EzwinOriginalWeaponSkin(void);
EzwinGloveOriginal EzwinOriginalGloveSkin(void);
kern_return_t EzwinInstallSkinHooks(uintptr_t base, uintptr_t weapon, uintptr_t glove);
