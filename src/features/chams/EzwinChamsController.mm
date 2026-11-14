#include "features/chams/EzwinChamsController.h"

static_assert(sizeof(EzwinChamsDrawPacket) == 240, "Native draw packet size");

static bool valid(const EzwinChamsAPI *api, void *object) {
    return object && (!api->valid || api->valid(object));
}

bool EzwinEnsureChamsMaterial(EzwinChamsController *c, const EzwinChamsAPI *api, int group) {
    if (valid(api, c->materials[group])) return true;
    if (!valid(api, c->viewShader) && !c->viewShaderAttempted) {
        c->viewShaderAttempted = true;
        void *bundle = api->bundle();
        if (bundle) {
            c->viewShader = api->loadShader(bundle, "viewmodelfx");
            if (c->viewShader && api->setHideFlags) api->setHideFlags(c->viewShader, 61);
        }
    }
    void *shader = c->viewShader;
    if (!valid(api, shader)) {
        if (!valid(api, c->fallbackShader)) {
            void *bundle = api->bundle();
            if (bundle) {
                c->fallbackShader = api->loadShader(bundle, "chamsshader");
                if (c->fallbackShader && api->setHideFlags) api->setHideFlags(c->fallbackShader, 61);
            }
        }
        shader = c->fallbackShader;
    }
    if (!shader || !api->createWithShader) return false;
    void *material = api->allocateMaterial();
    if (!material) return false;
    api->createWithShader(material, shader);
    if (api->setHideFlags) api->setHideFlags(material, 61);
    c->materials[group] = material;
    return true;
}

int EzwinChamsMeshGroup(void *mesh, EzwinChamsMeshes meshes) {
    if (!mesh) return -1;
    if (mesh == meshes.primary) return 0;
    if (mesh == meshes.secondary) return 1;
    if (meshes.attachments && meshes.attachmentCount > 0 && meshes.attachmentCount < 256) {
        for (int i = 0; i < meshes.attachmentCount; ++i) {
            if (mesh == meshes.attachments[i]) return 0;
        }
    }
    return -1;
}

static void updateStretch(EzwinChamsController *c, const EzwinChamsAPI *api, const float *value) {
    if (!value || (c->viewStretch == *value && c->stretchMaterials[0] == c->materials[0] &&
        c->stretchMaterials[1] == c->materials[1])) return;
    c->viewStretch = *value;
    c->stretchMaterials[0] = c->materials[0];
    c->stretchMaterials[1] = c->materials[1];
    if (api->material.setFloat) {
        for (int i = 0; i < 2; ++i) {
            if (c->materials[i]) api->material.setFloat(c->materials[i],
                api->material.string("_ViewStretch"), *value);
        }
    }
}

void EzwinApplyFirstPersonChams(EzwinChamsController *c, const EzwinChamsAPI *api,
    EzwinChamsMeshes meshes, EzwinChamsDrawPacket *packets, int begin, int end,
    bool enabled, const EzwinChamsGroup groups[2], const float *viewStretch) {
    if (!enabled || begin >= end || (!groups[0].mode && !groups[1].mode)) return;
    bool active[2] = {};
    void *originalMaterial[2] = {};
    for (int i = begin; i < end; ++i) {
        int group = EzwinChamsMeshGroup(packets[i].mesh, meshes);
        if (group >= 0 && groups[group].mode && !active[group]) {
            active[group] = true;
            originalMaterial[group] = packets[i].material;
            if (active[0] && active[1]) break;
        }
    }
    bool wrap[2] = {};
    for (int i = 0; i < 2; ++i) {
        if (active[i]) {
            active[i] = EzwinEnsureChamsMaterial(c, api, i);
            if (active[i]) wrap[i] = EzwinApplyChamsMaterial(&api->material, c->materials[i],
                groups[i].mode, groups[i].material, &c->cache[i]);
        }
    }
    if (!active[0] && !active[1]) return;
    updateStretch(c, api, viewStretch);
    static const char *textureNames[] = {"_Albedo", "_MainTex", "_SkinTex", "_BaseMap"};
    for (int i = 0; i < 2; ++i) {
        if (!active[i]) continue;
        void *source = originalMaterial[i];
        if (wrap[i] && source && api->getTexture && c->textureSource[i] != source) {
            c->textureSource[i] = source;
            c->texture[i] = nullptr;
            for (int j = 0; j < 4; ++j) {
                void *texture = api->getTexture(source, api->material.string(textureNames[j]));
                if (texture) { c->texture[i] = texture; break; }
            }
        }
        bool bind = wrap[i] && c->texture[i];
        if (c->textureBound[i] != bind || c->boundTexture[i] != c->texture[i]) {
            if (bind && api->setTexture) api->setTexture(c->materials[i],
                api->material.string("_BaseTex"), c->texture[i]);
            c->textureBound[i] = bind;
            c->boundTexture[i] = c->texture[i];
        }
    }
    for (int i = begin; i < end; ++i) {
        int group = EzwinChamsMeshGroup(packets[i].mesh, meshes);
        if (group >= 0 && active[group]) packets[i].material = c->materials[group];
    }
}
