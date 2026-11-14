#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
float EzwinNormalizeAngle(float angle);
float EzwinDeltaAngle(float current, float target);
float EzwinLerpAngle(float current, float target, float factor);
int EzwinBoneCount(uintptr_t actor);
uintptr_t EzwinBoneObject(uintptr_t actor, uint32_t index);
int EzwinTargetBoneIndex(uint32_t selection);
#ifdef __cplusplus
}
#endif
