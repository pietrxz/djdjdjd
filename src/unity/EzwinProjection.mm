#include "unity/EzwinProjection.h"
#include <math.h>
#pragma clang fp contract(off)

void EzwinUpdateProjection(EzwinProjection *p, void *camera, int32_t frame) {
    if (p->initialized && frame != -1 && p->frame == frame && p->camera == camera) return;
    EzwinMatrix projection = p->api.projection(camera);
    EzwinMatrix view = p->api.worldToLocal(p->api.transform(camera));
    const int rows[3] = {0, 1, 3};
    for (int column = 0; column < 4; ++column) {
        for (int i = 0; i < 3; ++i) {
            int row = rows[i];
            float value = fmaf(projection.value[row], view.value[column * 4],
                projection.value[4 + row] * view.value[column * 4 + 1]);
            value = fmaf(projection.value[8 + row], view.value[column * 4 + 2], value);
            p->clip[column][i] = fmaf(projection.value[12 + row], view.value[column * 4 + 3], value);
        }
    }
    p->camera = camera;
    p->frame = frame;
    p->initialized = true;
}

EzwinPosition EzwinProjectPosition(const EzwinProjection *p, EzwinPosition position) {
    float clip[3];
    for (int row = 0; row < 3; ++row) {
        float value = fmaf(p->clip[0][row], position.x, p->clip[1][row] * position.y);
        value = fmaf(p->clip[2][row], position.z, value);
        clip[row] = p->clip[3][row] + value;
    }
    float inverse = -1.0f / clip[2];
    return {p->width * fmaf(clip[0] * inverse, .5f, .5f),
        fmaf(-fmaf(clip[1] * inverse, .5f, .5f), p->height, p->height), -clip[2]};
}

EzwinPosition EzwinProjectESPPosition(void *context, EzwinPosition position) {
    return EzwinProjectPosition((EzwinProjection *)context, position);
}

EzwinPosition EzwinMatrixPosition(EzwinMatrix matrix) {
    return {matrix.value[12], matrix.value[13], matrix.value[14]};
}

EzwinPosition EzwinTransformPosition(EzwinMatrix matrix, EzwinPosition position) {
    EzwinPosition transformed;
    float *out = &transformed.x;
    for (int row = 0; row < 3; ++row) {
        float value = fmaf(matrix.value[row], position.x, matrix.value[4 + row] * position.y);
        value = fmaf(matrix.value[8 + row], position.z, value);
        out[row] = matrix.value[12 + row] + value;
    }
    return transformed;
}
