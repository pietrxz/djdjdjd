#include "features/aim/EzwinAimMath.h"
#include <math.h>

float EzwinNormalizeAngle(float angle) {
    if (angle <= 180.0f) {
        if (angle >= -180.0f) return angle;
        angle += 360.0f;
        if (angle >= -180.0f) return angle;
        float wrapped = fmodf(angle + 180.0f, 360.0f);
        if (wrapped < 0.0f) wrapped += 360.0f;
        return wrapped - 180.0f;
    }
    angle -= 360.0f;
    if (angle <= 180.0f) return angle;
    return fmodf(angle + 180.0f, 360.0f) - 180.0f;
}

float EzwinDeltaAngle(float current, float target) {
    return EzwinNormalizeAngle(target - current);
}

float EzwinLerpAngle(float current, float target, float factor) {
    return EzwinNormalizeAngle(fmaf(EzwinDeltaAngle(current, target), factor, current));
}
