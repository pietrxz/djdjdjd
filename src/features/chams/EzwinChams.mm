#include "features/chams/EzwinChams.h"

typedef struct {
    float noiseScale, baseDarkness, rimPower;
    int zTest, zWrite;
} ChamsPreset;

static const ChamsPreset presets[9] = {
    { 0.0f, 0.00f, 0.0f, 4, 1 },
    {35.0f, 0.05f, 2.5f, 4, 1 },
    {12.0f, 0.00f, 1.5f, 4, 0 },
    { 6.0f, 0.05f, 2.0f, 4, 1 },
    {20.0f, 0.05f, 2.5f, 4, 1 },
    {10.0f, 0.05f, 2.0f, 4, 1 },
    { 8.0f, 0.05f, 2.5f, 4, 1 },
    {15.0f, 0.05f, 2.0f, 4, 1 },
    {15.0f, 0.05f, 2.5f, 4, 1 }
};

static EzwinMaterialColor unpackColor(bool present, uint32_t packed) {
    if (!present) return {1.0f, 1.0f, 1.0f, 1.0f};
    return {(float)(packed & 255) / 255.0f,
            (float)((packed >> 8) & 255) / 255.0f,
            (float)((packed >> 16) & 255) / 255.0f,
            (float)(packed >> 24) / 255.0f};
}

static bool sameColor(EzwinMaterialColor a, EzwinMaterialColor b) {
    return a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a;
}

bool EzwinApplyChamsMaterial(const EzwinMaterialAPI *api, void *material,
    uint32_t mode, EzwinChamsOptions options, EzwinChamsCache *cache) {
    if (!material) return false;
    const ChamsPreset preset = presets[mode < 9 ? mode : 0];
    const EzwinMaterialColor color = unpackColor(options.hasColor, options.color);
    const EzwinMaterialColor rim = unpackColor(options.hasRimColor, options.rimColor);
    bool unchanged = cache->valid && cache->material == material && cache->mode == mode &&
        cache->wrapBase == options.wrapBase && cache->speed == options.speed &&
        cache->patternIntensity == options.patternIntensity &&
        cache->rimIntensity == options.rimIntensity &&
        cache->noiseScale == preset.noiseScale && cache->baseDarkness == preset.baseDarkness &&
        cache->rimPower == preset.rimPower && cache->zTest == preset.zTest &&
        cache->zWrite == preset.zWrite && sameColor(cache->color, color) &&
        sameColor(cache->rimColor, rim);
    if (!unchanged) {
        if (api->setFloat) {
            api->setFloat(material, api->string("_Pattern"), (float)(int32_t)(mode - 1));
            api->setFloat(material, api->string("_Speed"), options.speed);
            api->setFloat(material, api->string("_PatternIntensity"), options.patternIntensity);
            api->setFloat(material, api->string("_RimIntensity"), options.rimIntensity);
            api->setFloat(material, api->string("_NoiseScale"), preset.noiseScale);
            api->setFloat(material, api->string("_BaseDarkness"), preset.baseDarkness);
            api->setFloat(material, api->string("_RimPower"), preset.rimPower);
            api->setFloat(material, api->string("_WrapBase"), options.wrapBase ? 1.0f : 0.0f);
        }
        if (api->setInt) {
            api->setInt(material, api->string("_ZTest"), preset.zTest);
            api->setInt(material, api->string("_ZWrite"), preset.zWrite);
        }
        if (api->setColor) {
            api->setColor(material, api->string("_Color"), color);
            api->setColor(material, api->string("_RimColor"), rim);
        }
        if (api->setRenderQueue) api->setRenderQueue(material, preset.zWrite ? 4000 : 3000);
        *cache = {material, mode, true, options.wrapBase, options.speed,
            options.patternIntensity, options.rimIntensity, preset.noiseScale,
            preset.baseDarkness, preset.rimPower, preset.zTest, preset.zWrite, color, rim};
    }
    return options.wrapBase;
}
