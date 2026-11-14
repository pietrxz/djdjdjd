#include "features/aim/EzwinAimController.h"
#include "features/aim/EzwinAimMath.h"
#include <math.h>

float EzwinAimAxisStep(float error, float input, float previousDelta, float maximum, float blend, float delta) {
    if (fabsf(error) <= .3f) return 0;
    // Original udcops 0x289630: yield to opposing user input, then cap each axis.
    if (fabsf(input) >= .032f || fabsf(previousDelta) >= .05f) {
        if (error * previousDelta < 0 && fabsf(previousDelta) >= .02f) return 0;
        maximum = fminf(maximum * .25f, delta * 12);
        blend *= .25f;
    }
    return fmaxf(-maximum, fminf(maximum, blend * error));
}

bool EzwinAimDirection(EzwinPosition origin, EzwinPosition target, EzwinViewAngles *angles) {
    float x=target.x-origin.x, y=target.y-origin.y, z=target.z-origin.z;
    float horizontal=hypotf(x,z);
    if (!angles || !isfinite(horizontal) || !isfinite(y) || horizontal*horizontal+y*y < 1e-8f) return false;
    *angles = {-atan2f(y,horizontal)*57.2957795f, atan2f(x,z)*57.2957795f};
    return true;
}

bool EzwinAdvanceAim(EzwinAimState *state, const EzwinAimCandidate *candidates, int count,
    uintptr_t localActor, EzwinPosition origin, EzwinViewAngles current,
    EzwinAimSettings settings, float delta, EzwinViewAngles *output) {
    if (!state || !output || !isfinite(current.pitch) || !isfinite(current.yaw)) return false;
    EzwinAimTarget best = {};
    if (!EzwinSelectAimTarget(candidates,count,localActor,origin,settings.selection,&best)) {
        *state = {}; return false;
    }
    // Keep the current target while its screen score is within the native 15% margin.
    if (state->target && state->target != best.actor) for (int i=0;i<count && i<32;++i) {
        if (candidates[i].actor != state->target) continue;
        EzwinAimTarget previous = {};
        if (EzwinSelectAimTarget(candidates+i,1,localActor,origin,settings.selection,&previous) &&
            previous.screenDistanceSquared <= best.screenDistanceSquared*1.3225f) best=previous;
        break;
    }
    EzwinViewAngles desired;
    if (!EzwinAimDirection(origin,best.point,&desired)) { *state={}; return false; }
    if (!isfinite(delta) || delta<=0) delta=1.0f/60;
    delta=fmaxf(1.0f/240,fminf(1.0f/30,delta));
    float smooth=isfinite(settings.smoothness)?fmaxf(0,fminf(1,settings.smoothness)):0;
    float maximum=delta*(settings.fastAssist?1.6f:1)*(80-70*smooth);
    float blend=1-expf(-delta*(settings.fastAssist?11:8));
    EzwinViewAngles input = {};
    if (state->previousAvailable) input={EzwinDeltaAngle(state->previous.pitch,current.pitch),
        EzwinDeltaAngle(state->previous.yaw,current.yaw)};
    float pitch=EzwinAimAxisStep(EzwinDeltaAngle(current.pitch,desired.pitch),input.pitch,input.pitch,maximum,blend,delta);
    float yaw=EzwinAimAxisStep(EzwinDeltaAngle(current.yaw,desired.yaw),input.yaw,input.yaw,maximum,blend,delta);
    float magnitude=hypotf(pitch,yaw);
    if (magnitude>maximum) { pitch*=maximum/magnitude; yaw*=maximum/magnitude; }
    *output={EzwinNormalizeAngle(current.pitch+pitch),EzwinNormalizeAngle(current.yaw+yaw)};
    state->target=best.actor; state->previous=*output; state->previousAvailable=true;
    return pitch!=0 || yaw!=0;
}
