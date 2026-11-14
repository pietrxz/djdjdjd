#pragma once
#include "features/audio/EzwinSoundEvents.h"
#include <stdbool.h>

typedef struct {
    uintptr_t actor;
    int state;
    bool excluded;
    bool additionalCheckAvailable;
    bool additionalCheckPassed;
    int health;
    int boneCount;
    bool boneAvailable;
    EzwinPosition root;
    EzwinPosition bone;
    EzwinPosition screen;
    bool visible;
} EzwinAimCandidate;

typedef struct {
    bool enabled;
    bool visibilityCheck;
    bool firingCheck;
    bool firing;
    uint32_t targetBone;
    float fov;
    float maxDistance;
    float width;
    float height;
} EzwinAimOptions;

typedef struct {
    uintptr_t actor;
    EzwinPosition point;
    float screenDistanceSquared;
} EzwinAimTarget;

#ifdef __cplusplus
extern "C" {
#endif
bool EzwinSelectAimTarget(const EzwinAimCandidate *candidates, int count,
    uintptr_t localActor, EzwinPosition cameraPosition, EzwinAimOptions options,
    EzwinAimTarget *target);
#ifdef __cplusplus
}
#endif
