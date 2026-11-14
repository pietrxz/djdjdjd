#pragma once
#include <stdint.h>
#include <stdbool.h>

typedef struct { float r, g, b, a; } EzwinMaterialColor;
typedef struct {
    void *(*string)(const char *text);
    void (*setFloat)(void *material, void *name, float value);
    void (*setInt)(void *material, void *name, int value);
    void (*setColor)(void *material, void *name, EzwinMaterialColor value);
    void (*setRenderQueue)(void *material, int queue);
} EzwinMaterialAPI;

typedef struct {
    float speed, patternIntensity, rimIntensity;
    bool wrapBase;
    bool hasColor, hasRimColor;
    uint32_t color, rimColor;
} EzwinChamsOptions;

typedef struct {
    void *material;
    uint32_t mode;
    bool valid, wrapBase;
    float speed, patternIntensity, rimIntensity;
    float noiseScale, baseDarkness, rimPower;
    int zTest, zWrite;
    EzwinMaterialColor color, rimColor;
} EzwinChamsCache;

#ifdef __cplusplus
extern "C" {
#endif
bool EzwinApplyChamsMaterial(const EzwinMaterialAPI *api, void *material,
    uint32_t mode, EzwinChamsOptions options, EzwinChamsCache *cache);
#ifdef __cplusplus
}
#endif
