#pragma once
#include "features/chams/EzwinChams.h"

typedef struct {
    EzwinMaterialAPI material;
    bool (*valid)(void *object);
    void *(*bundle)(void);
    void *(*loadShader)(void *bundle, const char *name);
    void *(*allocateMaterial)(void);
    void (*createWithShader)(void *material, void *shader);
    void (*setHideFlags)(void *object, int flags);
    void *(*getTexture)(void *material, void *name);
    void (*setTexture)(void *material, void *name, void *texture);
} EzwinChamsAPI;

typedef struct {
    uint64_t reserved;
    void *mesh, *material;
    uint8_t payload[216];
} EzwinChamsDrawPacket;

typedef struct {
    void *primary, *secondary;
    void *const *attachments;
    int attachmentCount;
} EzwinChamsMeshes;

typedef struct { uint32_t mode; EzwinChamsOptions material; } EzwinChamsGroup;

typedef struct {
    void *viewShader, *fallbackShader;
    bool viewShaderAttempted;
    void *materials[2];
    EzwinChamsCache cache[2];
    void *textureSource[2], *texture[2], *boundTexture[2];
    bool textureBound[2];
    float viewStretch;
    void *stretchMaterials[2];
} EzwinChamsController;

#ifdef __cplusplus
extern "C" {
#endif
bool EzwinEnsureChamsMaterial(EzwinChamsController *controller, const EzwinChamsAPI *api,
    int group);
int EzwinChamsMeshGroup(void *mesh, EzwinChamsMeshes meshes);
void EzwinApplyFirstPersonChams(EzwinChamsController *controller, const EzwinChamsAPI *api,
    EzwinChamsMeshes meshes, EzwinChamsDrawPacket *packets, int begin, int end,
    bool enabled, const EzwinChamsGroup groups[2], const float *viewStretch);
#ifdef __cplusplus
}
#endif
