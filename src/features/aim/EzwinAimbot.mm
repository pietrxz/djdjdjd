#include "features/aim/EzwinAimbot.h"
#include "features/aim/EzwinAimMath.h"
#include <float.h>
#include <math.h>

static float DistanceSquared(EzwinPosition a, EzwinPosition b) {
    float x = a.x - b.x;
    float y = a.y - b.y;
    float z = a.z - b.z;
    return fmaf(z, z, fmaf(x, x, y * y));
}

static bool ValidTargetPosition(EzwinPosition position) {
    return isfinite(position.x) && isfinite(position.y) && isfinite(position.z)
        && fabsf(position.x) <= 100000.0f && fabsf(position.y) <= 100000.0f
        && fabsf(position.z) <= 100000.0f
        && (position.x != 0.0f || position.y != 0.0f || position.z != 0.0f);
}

bool EzwinSelectAimTarget(const EzwinAimCandidate *candidates, int count,
    uintptr_t localActor, EzwinPosition cameraPosition, EzwinAimOptions options,
    EzwinAimTarget *target) {
    if (!options.enabled || !candidates || !target || count <= 0 || options.targetBone >= 7 ||
        !isfinite(options.width) || !isfinite(options.height) || options.width <= 0 || options.height <= 0 ||
        !isfinite(options.fov) || options.fov < 0 || options.fov > 180 ||
        !isfinite(options.maxDistance) || options.maxDistance < 0 ||
        !isfinite(cameraPosition.x) || !isfinite(cameraPosition.y) || !isfinite(cameraPosition.z)) return false;
    if (count > 32) count = 32;

    const int boneIndex = EzwinTargetBoneIndex(options.targetBone);
    const float radius = (options.fov / 90.0f) * options.width * 0.25f;
    const float radiusSquared = radius * radius;
    const float maxDistanceSquared = options.maxDistance * options.maxDistance;
    float bestDistance = FLT_MAX;
    EzwinAimTarget best = {};
    bool found = false;

    for (int i = 0; i < count; i++) {
        const EzwinAimCandidate *candidate = &candidates[i];
        if (!candidate->actor || candidate->actor == localActor || candidate->state != 1
            || candidate->excluded) continue;
        if (candidate->additionalCheckAvailable && !candidate->additionalCheckPassed) continue;
        if (candidate->health <= 5 || candidate->boneCount <= boneIndex
            || !candidate->boneAvailable) continue;
        if (candidate->root.x == 0.0f && candidate->root.y == 0.0f
            && candidate->root.z == 0.0f) continue;
        if (!ValidTargetPosition(candidate->bone)
            || DistanceSquared(candidate->bone, candidate->root) > 100.0f) continue;
        if (!isfinite(candidate->screen.z) || candidate->screen.z <= 0.01f || !isfinite(candidate->screen.x)
            || !isfinite(candidate->screen.y) || !ValidTargetPosition(candidate->root)) continue;
        if (DistanceSquared(candidate->bone, cameraPosition) > maxDistanceSquared) continue;

        float x = candidate->screen.x - options.width * 0.5f;
        float y = candidate->screen.y - options.height * 0.5f;
        float distance = fmaf(x, x, y * y);
        if (distance >= radiusSquared || distance >= bestDistance) continue;
        if (options.visibilityCheck && !candidate->visible) continue;
        best = {candidate->actor, candidate->bone, distance};
        bestDistance = distance;
        found = true;
    }

    if (!found || (options.firingCheck && !options.firing)) return false;
    *target = best;
    return true;
}
