#pragma once
#include "features/aim/EzwinAimbot.h"

typedef struct { float pitch, yaw; } EzwinViewAngles;
typedef struct {
    EzwinAimOptions selection;
    bool fastAssist, showFOV;
    float smoothness;
} EzwinAimSettings;
typedef struct { uintptr_t target; EzwinViewAngles previous; bool previousAvailable; } EzwinAimState;

float EzwinAimAxisStep(float error, float input, float previousDelta, float maximum, float blend, float delta);
bool EzwinAimDirection(EzwinPosition origin, EzwinPosition target, EzwinViewAngles *angles);
bool EzwinAdvanceAim(EzwinAimState *state, const EzwinAimCandidate *candidates, int count,
    uintptr_t localActor, EzwinPosition origin, EzwinViewAngles current,
    EzwinAimSettings settings, float delta, EzwinViewAngles *output);
