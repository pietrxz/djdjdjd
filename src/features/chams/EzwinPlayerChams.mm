#include "features/chams/EzwinPlayerChams.h"
#include <math.h>
#include <limits.h>

static EzwinMaterialColor rgb(uint32_t color) {
    return {(float)(color & 255) / 255.0f, (float)((color >> 8) & 255) / 255.0f,
        (float)((color >> 16) & 255) / 255.0f, 1.0f};
}

void EzwinEnsurePlayerChamsMaterial(void **material, void *shader,
    const EzwinChamsAPI *api, int depthTest, int renderQueue) {
    if (*material && (!api->valid || api->valid(*material))) return;
    if (!shader || !api->createWithShader) return;
    void *created = api->allocateMaterial();
    if (!created) return;
    api->createWithShader(created, shader);
    if (api->setHideFlags) api->setHideFlags(created, 61);
    if (api->material.setInt) {
        void *property = api->material.string("_ZTest");
        if (property) api->material.setInt(created, property, depthTest);
    }
    if (api->material.setRenderQueue) api->material.setRenderQueue(created, renderQueue);
    *material = created;
}

void EzwinPlayerChamsColors(bool rainbow, bool timeAvailable, float time,
    uint32_t visibleColor, uint32_t hiddenColor, EzwinMaterialColor *visible,
    EzwinMaterialColor *hidden) {
    if (rainbow && timeAvailable) {
        *visible = {sinf(time), sinf(time + 2.0f), sinf(time + 4.0f), 1.0f};
        *hidden = {sinf(time + 1.0f), sinf(time + 3.0f), sinf(time + 5.0f), 1.0f};
    } else {
        *visible = visibleColor ? rgb(visibleColor) : EzwinMaterialColor{0, 1, 0, 1};
        *hidden = hiddenColor ? rgb(hiddenColor) : EzwinMaterialColor{1, 0, 0, 1};
    }
}

static bool same(EzwinMaterialColor a, EzwinMaterialColor b) {
    return a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a;
}

static void color(EzwinChamsColorCache *cache, const EzwinMaterialAPI *api, void *material,
    const char *property, EzwinMaterialColor value) {
    if (!material) return;
    if (!cache->valid || cache->material != material || !same(cache->value, value)) {
        api->setColor(material, api->string(property), value);
        *cache = {material, value, true};
    }
}

static void scalar(EzwinChamsFloatCache *cache, const EzwinMaterialAPI *api, void *material,
    const char *property, float value) {
    if (!material) return;
    if (!cache->valid || cache->material != material || cache->value != value) {
        api->setFloat(material, api->string(property), value);
        *cache = {material, value, true};
    }
}

void EzwinUpdatePlayerChamsMaterials(EzwinPlayerChamsState *state, const EzwinMaterialAPI *api,
    void *baseMaterial, void *wallMaterial, EzwinMaterialColor visible,
    EzwinMaterialColor hidden, EzwinPlayerChamsOptions options) {
    if (!api->setFloat || !api->setColor) return;
    color(state->colors + 0, api, baseMaterial, "_Color", visible);
    color(state->colors + 1, api, baseMaterial, "_ColorSec", hidden);
    color(state->colors + 2, api, wallMaterial, "_Color", hidden);
    color(state->colors + 3, api, wallMaterial, "_ColorSec", visible);
    static const char *properties[12] = {"_Wireframe", "_Style", "_PulsateRate", "_IsWallPass",
        "_FlowSpeed", "_OutlineExp", "_OutlineInner", "_NoiseScale", "_SmokeDrift",
        "_SmokeDensity", "_SmokeRimBoost", "_ZTest"};
    float values[12] = {options.wireframe ? 1.0f : 0.0f, (float)options.style,
        options.pulsate ? 1.5f : 0.0f, 0, options.flowSpeed,
        options.outlineExponent <= 0 ? 2.0f : options.outlineExponent, options.outlineInner,
        options.noiseScale <= 0 ? 4.0f : options.noiseScale, options.smokeDrift,
        options.smokeDensity <= 0 ? 1.0f : options.smokeDensity,
        options.smokeRimBoost <= 0 ? 1.4f : options.smokeRimBoost, 5.0f};
    for (int pass = 0; pass < 2; ++pass) {
        values[3] = (float)pass;
        for (int i = 0; i < (pass ? 12 : 11); ++i) scalar(&state->values[pass][i], api,
            pass ? wallMaterial : baseMaterial, properties[i], values[i]);
    }
}

void EzwinRecordChamsRenderer(EzwinPlayerChamsState *state, uintptr_t renderer, int32_t frame) {
    int empty = -1, oldest = 0;
    int32_t oldestFrame = INT_MAX;
    for (int i = 0; i < 64; ++i) {
        if (state->renderer[i] == renderer) { state->frame[i] = frame; return; }
        if (!state->renderer[i]) {
            if (empty < 0) empty = i;
        } else if (state->frame[i] < oldestFrame) {
            oldestFrame = state->frame[i]; oldest = i;
        }
    }
    int slot = empty >= 0 ? empty : oldest;
    state->renderer[slot] = renderer;
    state->frame[slot] = frame;
}

int32_t EzwinChamsRendererAge(const EzwinPlayerChamsState *state, uintptr_t renderer,
    bool frameAvailable, int32_t frame) {
    if (renderer && frameAvailable) {
        for (int i = 0; i < 64; ++i) {
            if (state->renderer[i] == renderer) return (int32_t)((uint32_t)frame - (uint32_t)state->frame[i]);
        }
    }
    return INT_MAX;
}

int EzwinApplyPlayerChamsPackets(EzwinChamsDrawPacket *packets, int begin, int end,
    bool enabled, bool tracked, void *baseMaterial, void *wallMaterial,
    EzwinAppendChamsPacket append, void *context) {
    if (!enabled || !tracked || !baseMaterial || !wallMaterial || !append || begin >= end) return 0;
    EzwinChamsDrawPacket copies[32];
    int count = 0;
    for (int i = begin; i < end && count < 32; ++i) {
        copies[count] = packets[i];
        copies[count++].material = wallMaterial;
        packets[i].material = baseMaterial;
    }
    for (int i = 0; i < count; ++i) append(context, copies + i);
    return count;
}
