#include "unity/EzwinOffsets1900.h"
#include "unity/EzwinUnity.h"
#include <string.h>

// This adapter targets the recovered Unity 1.90.0 image. Method lookup does not require exported IL2CPP symbols.
static uintptr_t unity;
static EzwinChamsAPI chams;
static void *cameraGetter, *projectionGetter, *worldToLocalGetter;
#ifdef EZWIN_HOOK_TESTING
static bool (*testValid)(void *);
static void (*testOcclusion)(uintptr_t, bool, void *);
extern "C" void EzwinTestUnityRendererAPI(bool (*valid)(void *), void (*setter)(uintptr_t, bool, void *)) {
    testValid = valid; testOcclusion = setter;
}
#endif
struct AssemblyVector { void **begin, **end, **capacity; };

uintptr_t EzwinUnityBase(void) { return unity; }
void EzwinUnitySetBase(uintptr_t base) {
    if (unity == base) return;
    unity = base;
    cameraGetter = projectionGetter = worldToLocalGetter = nullptr;
    chams = {};
}

static void *image(const char *name) {
    if (!unity || !name) return nullptr;
    AssemblyVector *assemblies = ((AssemblyVector *(*)(void))(unity + EzwinUF_Assemblies))();
    if (!assemblies || !assemblies->begin || assemblies->end < assemblies->begin) return nullptr;
    for (void **item = assemblies->begin; item < assemblies->end; ++item) {
        if (!*item) continue;
        void *current = *(void **)*item;
        const char *currentName = current ? *(const char **)current : nullptr;
        if (currentName && strstr(currentName, name)) return current;
    }
    return nullptr;
}

void *EzwinUnityClass(const char *assembly, const char *space, const char *name) {
    void *current = image(assembly);
    return current ? ((void *(*)(void *, const char *, const char *))(unity + EzwinUF_ClassFromName))(current, space, name) : nullptr;
}

void *EzwinUnityMethod(const char *assembly, const char *space, const char *name, const char *method, int arguments) {
    void *type = EzwinUnityClass(assembly, space, name);
    if (!type) return nullptr;
    void **info = ((void **(*)(void *, const char *, int, int, int))(unity + EzwinUF_MethodLookup))(type, method, arguments, 0, 0);
    return info ? *info : nullptr;
}

void *EzwinUnityString(const char *text) {
    return unity && text ? ((void *(*)(const char *, size_t))(unity + EzwinUF_StringNewLen))(text, strlen(text)) : nullptr;
}

void *EzwinUnityAllocate(const char *assembly, const char *space, const char *name) {
    void *type = EzwinUnityClass(assembly, space, name);
    return type ? ((void *(*)(void *))(unity + EzwinUF_Allocate))(type) : nullptr;
}

bool EzwinUnityValid(void *object) {
#ifdef EZWIN_HOOK_TESTING
    if (testValid) return object && testValid(object);
#endif
    return object && unity && ((bool (*)(void *, void *))(unity + EzwinUF_ObjectValid))(object, nullptr);
}
int32_t EzwinUnityFrame(void) { return unity ? ((int32_t (*)(void *))(unity + EzwinUF_FrameCount))(nullptr) : -1; }
float EzwinUnityRealtime(void) { return unity ? ((float (*)(void *))(unity + EzwinUF_Realtime))(nullptr) : 0; }
int EzwinUnityVisibilityMask(void) {
    if (!unity) return -1;
    uintptr_t type = *(uintptr_t *)(unity + EzwinSlot_VisibilityType);
    if (type <= unity || type & 7) return -1;
    uintptr_t fields = type ? *(uintptr_t *)(type + EzwinField_TypeStaticFields) : 0;
    int mask = -1;
    if (fields) memcpy(&mask, (void *)(fields + EzwinField_VisibilityMask), 4);
    return mask;
}
void EzwinUnityRendererOcclusion(uintptr_t component, bool allowed) {
    if (!unity || !EzwinUnityValid((void *)component)) return;
    uintptr_t renderer = 0;
    memcpy(&renderer, (const void *)(component + EzwinField_GameComponentRenderer), sizeof(renderer));
    if (!EzwinUnityValid((void *)renderer)) return;
#ifdef EZWIN_HOOK_TESTING
    if (testOcclusion) { testOcclusion(renderer, allowed, nullptr); return; }
#endif
    // Unwrap the game draw component before calling the Unity Renderer method.
    ((void (*)(uintptr_t, bool, void *))(unity + EzwinUF_RendererOcclusion))(renderer, allowed, nullptr);
}
void *EzwinUnityTransform(void *component) {
    return component && unity ? ((void *(*)(void *, void *))(unity + EzwinUF_Transform))(component, nullptr) : nullptr;
}
EzwinMatrix EzwinUnityLocalToWorld(void *transform) {
    return transform && unity ? ((EzwinMatrix (*)(void *, void *))(unity + EzwinUF_LocalToWorld))(transform, nullptr) : EzwinMatrix{};
}

void *EzwinUnityCamera(void) { return cameraGetter ? ((void *(*)(void *))cameraGetter)(nullptr) : nullptr; }
EzwinMatrix EzwinUnityProjection(void *camera) {
    return camera && projectionGetter ? ((EzwinMatrix (*)(void *, void *))projectionGetter)(camera, nullptr) : EzwinMatrix{};
}
EzwinMatrix EzwinUnityWorldToLocal(void *transform) {
    return transform && worldToLocalGetter ? ((EzwinMatrix (*)(void *, void *))worldToLocalGetter)(transform, nullptr) : EzwinMatrix{};
}
uintptr_t EzwinUnityContext(void) {
    if (!unity) return 0;
    uintptr_t type = *(uintptr_t *)(unity + EzwinSlot_ContextType);
    if (type <= unity || type & 7) return 0;
    uintptr_t fields = type ? *(uintptr_t *)(type + EzwinField_TypeStaticFields) : 0;
    uintptr_t context = fields ? *(uintptr_t *)fields : 0;
    return context;
}
static uintptr_t localManager(void) { uintptr_t context=EzwinUnityContext(); return context?*(uintptr_t *)(context+EzwinField_ContextManager):0; }
uintptr_t EzwinUnityLocalActor(void) {
    uintptr_t manager = localManager();
    return manager ? ((uintptr_t (*)(uintptr_t, void *))(unity + EzwinUF_LocalActor))(manager, nullptr) : 0;
}
uintptr_t EzwinUnityLocalSkinActor(void) {
    uintptr_t manager = localManager();
    return manager ? ((uintptr_t (*)(uintptr_t, void *))(unity + EzwinUF_LocalSkinActor))(manager, nullptr) : 0;
}

uint32_t EzwinUnityDecodeValue(uintptr_t actor, size_t field, size_t classSlot) {
    if (!unity || !actor) return 0;
    ((void (*)(void *))(unity + EzwinUF_MetadataInitialize))((void *)(unity + classSlot));
    void *method = *(void **)(unity + classSlot);
    if (!method) return 0;
    uint32_t encrypted[4] = {}, output[4] = {};
    memcpy(encrypted, (void *)(actor + field), 12);
    ((void (*)(void *, void *, void *))(unity + EzwinUF_DecodeValue))(encrypted, output, method);
    return output[0];
}

static uintptr_t actorFrame(uintptr_t actor) {
    uintptr_t owner = actor ? *(uintptr_t *)(actor + EzwinField_ActorOwner) : 0;
    uintptr_t state = owner ? *(uintptr_t *)(owner + EzwinField_OwnerState) : 0;
    return state ? *(uintptr_t *)(state + EzwinField_StateFrame) : 0;
}

static void *metadata(size_t slot) {
    ((void (*)(void *))(unity + EzwinUF_MetadataInitialize))((void *)(unity + slot));
    return *(void **)(unity + slot);
}

static bool contains(uintptr_t dictionary, int key, size_t slot) {
    void *method = metadata(slot);
    return dictionary && method &&
        ((bool (*)(uintptr_t, int, void *))(unity + EzwinUF_DictionaryContains))(dictionary, key, method);
}

static uintptr_t actorData(uintptr_t actor) {
    if (!unity || !actor) return 0;
    uintptr_t frame = actorFrame(actor), dictionary = frame ? *(uintptr_t *)(frame + EzwinField_FrameDictionary) : 0;
    if (!contains(dictionary, *(int *)(actor + EzwinField_ActorIdentifier), EzwinSlot_ActorDictionaryContains)) return 0;
    return ((uintptr_t (*)(uintptr_t, void *))(unity + EzwinUF_ActorData))(actor, nullptr);
}

int EzwinUnityHealth(uintptr_t actor) {
    uintptr_t data = actorData(actor);
    return data ? *(int *)(data + EzwinField_ActorDataHealth) : 0;
}

EzwinViewAngles EzwinUnityViewAngles(uintptr_t actor) {
    return actor && unity ? ((EzwinViewAngles (*)(uintptr_t,void *))(unity+EzwinUF_ViewAngles))(actor,nullptr) : EzwinViewAngles{};
}
void EzwinUnitySetViewAngles(uintptr_t actor, EzwinViewAngles angles) {
    if(actor && unity)((void (*)(uintptr_t,EzwinViewAngles,void *))(unity+EzwinUF_SetViewAngles))(actor,angles,nullptr);
}
bool EzwinUnityFiring(uintptr_t actor) {
    return actor && unity && ((bool (*)(uintptr_t,void *))(unity+EzwinUF_Firing))(actor,nullptr);
}
int EzwinUnityArmor(uintptr_t actor, int kind) {
    if (!unity || !actor || kind < 0 || kind > 1) return 0;
    uintptr_t frame = actorFrame(actor), dictionary = frame ? *(uintptr_t *)(frame + EzwinField_FrameDictionary) : 0;
    if (!dictionary) return 0;
    int identifier = ((int (*)(uintptr_t, int, int, void *))(unity + EzwinUF_ArmorIdentifier))
        (frame, *(int *)(actor + EzwinField_ActorIdentifier), kind, nullptr);
    if (identifier <= 0xffff || !contains(dictionary, identifier, EzwinSlot_ArmorDictionaryContains)) return 0;
    void *method = metadata(EzwinSlot_ArmorDictionaryValue);
    if (!method) return 0;
    int *value = ((int *(*)(uintptr_t, int, void *))(unity + EzwinUF_DictionaryValue))(dictionary, identifier, method);
    return value && *value > 0 ? *value : 0;
}

bool EzwinUnityScoped(uintptr_t actor) {
    return actorData(actor) && ((bool (*)(uintptr_t, void *))(unity + EzwinUF_Scoped))(actor, nullptr);
}

bool EzwinUnityInvulnerable(uintptr_t actor) {
    return actorData(actor) && ((bool (*)(uintptr_t, void *))(unity + EzwinUF_Invulnerable))(actor, nullptr);
}
bool EzwinUnityLineBlocked(EzwinPosition from, EzwinPosition to, int mask) {
    return unity && ((bool (*)(EzwinPosition, EzwinPosition, int, int, void *))(unity + EzwinUF_LineBlocked))
        (from, to, mask, 0, nullptr);
}

static void setFloat(void *material, void *name, float value) {
    ((void (*)(void *, void *, float, void *))(unity + EzwinUF_MaterialFloat))(material, name, value, nullptr);
}
static void setInt(void *material, void *name, int value) {
    ((void (*)(void *, void *, int, void *))(unity + EzwinUF_MaterialInt))(material, name, value, nullptr);
}
static void setColor(void *material, void *name, EzwinMaterialColor value) {
    ((void (*)(void *, void *, EzwinMaterialColor, void *))(unity + EzwinUF_MaterialColor))(material, name, value, nullptr);
}
static void setQueue(void *material, int value) {
    ((void (*)(void *, int, void *))(unity + EzwinUF_MaterialQueue))(material, value, nullptr);
}
static void *getTexture(void *material, void *name) {
    return ((void *(*)(void *, void *, void *))(unity + EzwinUF_MaterialGetTexture))(material, name, nullptr);
}
static void setTexture(void *material, void *name, void *texture) {
    ((void (*)(void *, void *, void *, void *))(unity + EzwinUF_MaterialSetTexture))(material, name, texture, nullptr);
}
static void *newMaterial(void) { return EzwinUnityAllocate("UnityEngine.CoreModule.dll", "UnityEngine", "Material"); }
static void createMaterial(void *material, void *shader) {
    ((void (*)(void *, void *, void *))(unity + EzwinUF_MaterialCreate))(material, shader, nullptr);
}
static void hideFlags(void *object, int flags) {
    ((void (*)(void *, int, void *))(unity + EzwinUF_HideFlags))(object, flags, nullptr);
}
static void *bundle(void) { return EzwinLoadShaderBundle(nullptr); }

bool EzwinBindUnity1900(uintptr_t base) {
    if (!base) return false;
    EzwinUnitySetBase(base);
    // Exact managed entries verified against the UUID-gated 1.90.0 image.
    cameraGetter = (void *)(base + EzwinUF_CameraMain);
    projectionGetter = (void *)(base + EzwinUF_CameraProjection);
    worldToLocalGetter = (void *)(base + EzwinUF_WorldToLocal);
    chams = {{EzwinUnityString, setFloat, setInt, setColor, setQueue}, EzwinUnityValid,
        bundle, EzwinLoadShader, newMaterial, createMaterial, hideFlags, getTexture, setTexture};
    return cameraGetter && projectionGetter && worldToLocalGetter;
}
const EzwinChamsAPI *EzwinUnityChamsAPI(void) { return unity && chams.valid ? &chams : nullptr; }
