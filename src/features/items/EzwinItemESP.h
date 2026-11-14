#pragma once
#include "unity/EzwinProjection.h"
#include "features/esp/EzwinESPDraw.h"
typedef struct { bool enabled; uint32_t color; } EzwinItemOptions;
typedef struct {
    bool (*valid)(void *);
    void *(*transform)(void *);
    EzwinMatrix (*matrix)(void *);
    uintptr_t (*icon)(const char *,float,float *);
    const char *(*weaponName)(int);
} EzwinItemAPI;
typedef struct {
    uintptr_t actor, texture;
    EzwinPosition world;
    EzwinPoint screen;
    float distance,width,height,alpha;
    int definition;
    char label[24];
} EzwinItemSample;
typedef struct { EzwinItemSample items[256]; int count; } EzwinItemState;
void EzwinCollectItems(EzwinItemState *state, uintptr_t context, EzwinPosition camera,
    const EzwinProjection *projection, const EzwinItemAPI *api);
void EzwinRenderItems(const EzwinItemState *state, const EzwinProjection *projection, uint32_t color);
