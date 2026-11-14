#pragma once
#import <Foundation/Foundation.h>
#include "unity/EzwinProjection.h"
#include "features/chams/EzwinChamsController.h"
#include "features/aim/EzwinAimController.h"

bool EzwinBindUnity1900(uintptr_t base);
void EzwinUnitySetBase(uintptr_t base);
uintptr_t EzwinUnityBase(void);
void *EzwinUnityClass(const char *assembly, const char *space, const char *name);
void *EzwinUnityMethod(const char *assembly, const char *space, const char *name,
    const char *method, int arguments);
void *EzwinUnityString(const char *text);
void *EzwinUnityAllocate(const char *assembly, const char *space, const char *name);
bool EzwinUnityValid(void *object);
int32_t EzwinUnityFrame(void);
float EzwinUnityRealtime(void);
int EzwinUnityVisibilityMask(void);
void EzwinUnityRendererOcclusion(uintptr_t renderer, bool allowed);
void *EzwinUnityCamera(void);
void *EzwinUnityTransform(void *component);
EzwinMatrix EzwinUnityLocalToWorld(void *transform);
EzwinMatrix EzwinUnityWorldToLocal(void *transform);
EzwinMatrix EzwinUnityProjection(void *camera);
uintptr_t EzwinUnityLocalActor(void);
uintptr_t EzwinUnityContext(void);
EzwinViewAngles EzwinUnityViewAngles(uintptr_t actor);
void EzwinUnitySetViewAngles(uintptr_t actor, EzwinViewAngles angles);
bool EzwinUnityFiring(uintptr_t actor);
uintptr_t EzwinUnityLocalSkinActor(void);
uint32_t EzwinUnityDecodeValue(uintptr_t actor, size_t field, size_t classSlot);
int EzwinUnityHealth(uintptr_t actor);
int EzwinUnityArmor(uintptr_t actor, int kind);
bool EzwinUnityScoped(uintptr_t actor);
bool EzwinUnityInvulnerable(uintptr_t actor);
int EzwinUnityWeaponID(uintptr_t actor);
const char *EzwinWeaponName(int weapon);
bool EzwinUnityLineBlocked(EzwinPosition from, EzwinPosition to, int mask);
const EzwinChamsAPI *EzwinUnityChamsAPI(void);
void *EzwinLoadShaderBundle(NSError **error);
void *EzwinLoadShader(void *bundle, const char *name);
NSData *EzwinShaderBundleData(void);
