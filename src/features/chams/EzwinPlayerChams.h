#pragma once
#include "features/chams/EzwinChamsController.h"

typedef struct {
    bool wireframe, pulsate;
    int style;
    float flowSpeed, outlineExponent, outlineInner, noiseScale;
    float smokeDrift, smokeDensity, smokeRimBoost;
} EzwinPlayerChamsOptions;

typedef struct { void *material; float value; bool valid; } EzwinChamsFloatCache;
typedef struct { void *material; EzwinMaterialColor value; bool valid; } EzwinChamsColorCache;
typedef struct {
    EzwinChamsColorCache colors[4];
    EzwinChamsFloatCache values[2][12];
    uintptr_t renderer[64];
    int32_t frame[64];
} EzwinPlayerChamsState;

typedef void (*EzwinAppendChamsPacket)(void *context, const EzwinChamsDrawPacket *packet);

#ifdef __cplusplus
extern "C" {
#endif
void EzwinPlayerChamsColors(bool rainbow, bool timeAvailable, float time,
    uint32_t visibleColor, uint32_t hiddenColor, EzwinMaterialColor *visible,
    EzwinMaterialColor *hidden);
void EzwinEnsurePlayerChamsMaterial(void **material, void *shader,
    const EzwinChamsAPI *api, int depthTest, int renderQueue);
void EzwinUpdatePlayerChamsMaterials(EzwinPlayerChamsState *state, const EzwinMaterialAPI *api,
    void *baseMaterial, void *wallMaterial, EzwinMaterialColor visible,
    EzwinMaterialColor hidden, EzwinPlayerChamsOptions options);
void EzwinRecordChamsRenderer(EzwinPlayerChamsState *state, uintptr_t renderer, int32_t frame);
int32_t EzwinChamsRendererAge(const EzwinPlayerChamsState *state, uintptr_t renderer,
    bool frameAvailable, int32_t frame);
int EzwinApplyPlayerChamsPackets(EzwinChamsDrawPacket *packets, int begin, int end,
    bool enabled, bool tracked, void *baseMaterial, void *wallMaterial,
    EzwinAppendChamsPacket append, void *context);
#ifdef __cplusplus
}
#endif
