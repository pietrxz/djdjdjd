#pragma once
#include "features/esp/EzwinActorCollector.h"

typedef struct {
    EzwinPosition position;
    float time;
    uint8_t category, padding[3];
} EzwinSoundTrailPoint;
typedef struct {
    uintptr_t actor;
    EzwinPosition previous;
    float distance;
    EzwinSoundTrailPoint points[6];
    int next, frame;
} EzwinSoundTrail;
typedef struct {
    uintptr_t actor;
    float alpha;
    EzwinPosition position;
    uint32_t color;
    unsigned frame;
} EzwinOffscreenActor;
typedef struct {
    bool arrows, sound, movement, shots, offscreenSoundCircles;
    float arrowSize, arrowRadius, soundScale;
    uint32_t arrowVisible, arrowHidden, movementColor, shotColor;
} EzwinWorldESPOptions;
typedef struct {
    void *context;
    void (*line)(void *, EzwinPoint a, EzwinPoint b, uint32_t color, float thickness);
    void (*polygon)(void *, const EzwinPoint *points, int count, uint32_t color);
    void (*circle)(void *, EzwinPoint center, float radius, uint32_t color, float thickness);
} EzwinWorldESPPainter;
typedef struct {
    EzwinSoundTrail trails[32];
    EzwinOffscreenActor arrows[32];
    uint32_t cachedArrowVisible, cachedArrowHidden;
    unsigned frame;
    float time;
} EzwinWorldESPState;

void EzwinRecordWorldShot(EzwinWorldESPState *state, uintptr_t actor, EzwinPosition position);
void EzwinRenderWorldESP(EzwinWorldESPState *state, const EzwinActorCollector *collector,
    const EzwinWorldESPOptions *options, const EzwinWorldESPPainter *painter, float delta);
