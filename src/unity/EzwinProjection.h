#pragma once
#include "features/audio/EzwinSoundEvents.h"
#include <stdint.h>
#include <stdbool.h>

typedef struct { float value[16]; } EzwinMatrix;
typedef struct {
    void *(*transform)(void *component);
    EzwinMatrix (*projection)(void *camera);
    EzwinMatrix (*worldToLocal)(void *transform);
} EzwinProjectionAPI;
typedef struct {
    EzwinProjectionAPI api;
    float width, height;
    void *camera;
    int32_t frame;
    float clip[4][3];
    bool initialized;
} EzwinProjection;

#ifdef __cplusplus
extern "C" {
#endif
void EzwinUpdateProjection(EzwinProjection *projection, void *camera, int32_t frame);
EzwinPosition EzwinProjectPosition(const EzwinProjection *projection, EzwinPosition position);
EzwinPosition EzwinProjectESPPosition(void *context, EzwinPosition position);
EzwinPosition EzwinMatrixPosition(EzwinMatrix matrix);
EzwinPosition EzwinTransformPosition(EzwinMatrix matrix, EzwinPosition position);
#ifdef __cplusplus
}
#endif
