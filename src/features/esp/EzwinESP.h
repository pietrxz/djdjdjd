#pragma once
#include "features/esp/EzwinESPGeometry.h"
#include "features/audio/EzwinSoundEvents.h"

typedef struct {
    bool available, visible;
    EzwinPosition center, axes[3];
    float radius;
} EzwinESPHitbox;

typedef struct {
    uintptr_t actor;
    bool self, eligible;
    float alpha;
    EzwinPosition screen, bones[11];
    bool boneVisible[11], skeletonSuppressed;
    bool hasBounds;
    EzwinPosition bounds[8];
    EzwinESPHitbox hitboxes[11];
    int health, armor, maximumArmor;
    EzwinESPLabelContent labels;
    uintptr_t weaponTexture;
} EzwinESPActor;

typedef struct {
    bool enabled, selfESP;
    bool lines, box3D, box2D, skeleton, hitboxes, hitboxValues, headCircle;
    int lineOrigin, detailsStyle;
    float screenWidth, screenHeight;
    uint32_t color, healthColor, armorColor, textColor;
    uint32_t skeletonVisible, skeletonHidden, hitboxVisible, hitboxHidden;
    EzwinESPPlacement placement;
    int order[16];
} EzwinESPOptions;

typedef EzwinPosition (*EzwinESPProjection)(void *context, EzwinPosition world);
typedef EzwinPoint (*EzwinESPTextSize)(void *context, const char *text, float size);

#ifdef __cplusplus
extern "C" {
#endif
void EzwinRenderActorESP(const EzwinESPActor *actor, const EzwinESPOptions *options,
    EzwinESPProjection project, EzwinESPTextSize textSize, void *context);
#ifdef __cplusplus
}
#endif
