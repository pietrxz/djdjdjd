#include "unity/EzwinOffsets1900.h"
#include "features/esp/EzwinActorCollector.h"
#include "unity/EzwinUnity.h"
#include "features/aim/EzwinAimMath.h"
#include "core/EzwinDiagnostics.h"
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#pragma clang fp contract(off)

static uintptr_t pointer(uintptr_t address) { uintptr_t value; memcpy(&value, (void *)address, 8); return value; }
static int integer(uintptr_t address) { int value; memcpy(&value, (void *)address, 4); return value; }
static float number(uintptr_t address) { float value; memcpy(&value, (void *)address, 4); return value; }
static bool valid(uintptr_t object) { return object && EzwinUnityValid((void *)object); }
static uint64_t uptimeNanoseconds(void) {
    struct timespec now; clock_gettime(CLOCK_UPTIME_RAW, &now);
    return (uint64_t)now.tv_sec * 1000000000 + now.tv_nsec;
}
static uint64_t milliseconds(void) {
    struct timespec now; clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint64_t)now.tv_sec * 1000 + (uint64_t)now.tv_nsec / 1000000;
}
static float length(EzwinPosition point) { return sqrtf(point.y * point.y + point.x * point.x + point.z * point.z); }

static int playerValue(uintptr_t player, size_t field, unsigned limit) {
    uintptr_t wrapper = player ? pointer(player + field) : 0;
    int value = wrapper ? integer(wrapper + EzwinField_ScalarValue) : 0;
    return (unsigned)value < limit ? value : 0;
}

static void playerName(uintptr_t player, char output[64]) {
    output[0] = 0;
    uintptr_t wrapper = player ? pointer(player + EzwinField_PlayerName) : 0;
    uintptr_t text = wrapper ? pointer(wrapper + EzwinField_WrappedString) : 0;
    int count = text ? integer(text + EzwinField_StringLength) : 0;
    if (count < 1 || count > 99) return;
    NSString *name = [[NSString alloc] initWithCharacters:(const unichar *)(text + EzwinField_StringChars) length:count];
    const char *utf8 = name.UTF8String;
    if (utf8) { size_t size = strnlen(utf8, 63); memcpy(output, utf8, size); output[size] = 0; }
}

static void armor(EzwinCollectedActor *snapshot, uintptr_t actor) {
    int sum = 0;
    snapshot->helmet = snapshot->vest = false;
    for (int kind = 0; kind < 2; ++kind) {
        int value = EzwinUnityArmor(actor, kind);
        sum += value;
        if (value > 0) {
            snapshot->helmet |= kind == 1;
            snapshot->vest |= kind == 0;
        }
    }
    snapshot->esp.armor = sum;
    if (sum > snapshot->esp.maximumArmor) snapshot->esp.maximumArmor = sum;
}

static void bones(EzwinActorCollector *collector, EzwinCollectedActor *snapshot, EzwinPosition camera) {
    snapshot->sampledBones=0;
    int count = EzwinBoneCount(snapshot->esp.actor);
    for (int i = 0; i < count; ++i) {
        if((collector->fields & EzwinCollectAim) && !(collector->fields & EzwinCollectGeometry) && i!=collector->aimBone)continue;
        uintptr_t bone = EzwinBoneObject(snapshot->esp.actor, i);
        void *transform = bone ? EzwinUnityTransform((void *)bone) : nullptr;
        if (!EzwinUnityValid(transform)) continue;
        EzwinPosition world = EzwinMatrixPosition(EzwinUnityLocalToWorld(transform));
        snapshot->worldBones[i] = world;
        snapshot->sampledBones|=(uint16_t)(1u<<i);
        EzwinPosition projected = world;
        if (i == 10) projected.y += .1f;
        snapshot->esp.bones[i] = EzwinProjectPosition(&collector->projection, projected);
        if ((collector->fields & EzwinCollectVisibility) && (collector->allBoneVisibility || i == 5))
            snapshot->esp.boneVisible[i] = !EzwinUnityLineBlocked(camera, world, collector->layerMask);
        if (!collector->sampleHitboxes) continue;
        uintptr_t hitbox = pointer(bone + EzwinField_BoneHitbox), hitboxTransform = hitbox ? pointer(hitbox + EzwinField_HitboxTransform) : 0;
        if (!hitboxTransform) continue;
        EzwinMatrix matrix = EzwinUnityLocalToWorld((void *)hitboxTransform);
        EzwinPosition local = {number(hitbox + EzwinField_HitboxCenterX), number(hitbox + EzwinField_HitboxCenterY), number(hitbox + EzwinField_HitboxCenterZ)};
        EzwinESPHitbox *result = snapshot->esp.hitboxes + i;
        // The original center uses separate products and additions rather than fused matrix math.
        result->center = {matrix.value[12] + local.y * matrix.value[4] + local.x * matrix.value[0] + local.z * matrix.value[8],
            matrix.value[13] + local.y * matrix.value[5] + local.x * matrix.value[1] + local.z * matrix.value[9],
            matrix.value[14] + local.y * matrix.value[6] + local.x * matrix.value[2] + local.z * matrix.value[10]};
        for (int axis = 0; axis < 3; ++axis)
            result->axes[axis] = {matrix.value[axis * 4], matrix.value[axis * 4 + 1], matrix.value[axis * 4 + 2]};
        result->radius = fmaxf(length(result->axes[0]), fmaxf(length(result->axes[1]), length(result->axes[2])));
        result->available = true;
        result->visible = snapshot->esp.boneVisible[i];
    }
}

void EzwinAdvanceActorFades(EzwinActorCollector *collector, uint64_t nanoseconds) {
    if (nanoseconds - collector->fadeTime <= 14999999) return;
    collector->fadeTime = nanoseconds;
    for (int i = 0; i < 32; ++i) {
        EzwinCollectedActor *actor = collector->actors + i;
        if (!actor->esp.actor) continue;
        bool alive = valid(actor->esp.actor) && EzwinUnityHealth(actor->esp.actor) > 0;
        if (alive) actor->esp.alpha = fminf(actor->esp.alpha + .08f, 1);
        else if (actor->esp.alpha > 0) actor->esp.alpha -= .08f;
    }
}

EzwinCollectedActor *EzwinCollectActor(EzwinActorCollector *collector, uintptr_t actor) {
    EzwinTraceCheckpoint(16, "collector: validating actor");
    if (!collector || !valid(actor)) return nullptr;
    EzwinCollectedActor *snapshot = nullptr, *empty = nullptr;
    for (int i = 0; i < 32; ++i) {
        EzwinCollectedActor *current = collector->actors + i;
        if (current->esp.actor == actor) { snapshot = current; break; }
        if (current->esp.actor && !valid(current->esp.actor) && current->esp.alpha <= 0) *current = {};
        if (!current->esp.actor && !empty) empty = current;
    }
    if (!snapshot) snapshot = empty;
    if (!snapshot) return nullptr;
    int maximumArmor = snapshot->esp.maximumArmor;
    float alpha = snapshot->esp.alpha;
    EzwinTraceCheckpoint(17, "collector: reading health");
    int health = EzwinUnityHealth(actor);
    if (health > 0) {
        float labelAlpha[16]; memcpy(labelAlpha, snapshot->labelAlpha, sizeof(labelAlpha));
        *snapshot = {};
        memcpy(snapshot->labelAlpha, labelAlpha, sizeof(labelAlpha));
        snapshot->team = -1;
    }
    snapshot->esp.actor = actor;
    snapshot->sampledFrame=collector->frame;
    snapshot->sampledBones=0;
    snapshot->esp.alpha = alpha;
    snapshot->esp.health = health;
    snapshot->esp.maximumArmor = maximumArmor;
    snapshot->esp.self = actor == collector->localActor;
    if (collector->fields & EzwinCollectArmor) {
        EzwinTraceCheckpoint(18, "collector: reading armor");
        armor(snapshot, actor);
    }
    EzwinTraceCheckpoint(19, "collector: reading player and team");
    uintptr_t controller = pointer(actor + EzwinField_ActorController), player = controller ? pointer(controller + EzwinField_ControllerPlayer) : 0;
    uintptr_t team = player ? pointer(player + EzwinField_PlayerTeam) : 0;
    snapshot->team = team ? integer(team + EzwinField_ScalarValue) : -1;
    snapshot->esp.eligible = collector->localTeam >= 0 && snapshot->team >= 0 && collector->localTeam != snapshot->team;
    if (collector->fields & EzwinCollectName) playerName(player, snapshot->name);
    if (collector->fields & EzwinCollectStatistics) {
        snapshot->money = playerValue(player, EzwinField_PlayerMoney, 1000000);
        for (int i = 0; i < 3; ++i) snapshot->statistics[i] = playerValue(player, EzwinField_PlayerStatistics + i * 8, 10000);
        snapshot->ping = controller && (unsigned)integer(controller + EzwinField_ControllerPing) < 100000 ? integer(controller + EzwinField_ControllerPing) : 0;
    }
    EzwinPosition camera = {};
    void *cameraTransform = nullptr, *transform = nullptr;
    if (collector->fields & EzwinCollectPosition) {
        EzwinTraceCheckpoint(20, "collector: reading transforms");
        cameraTransform = EzwinUnityTransform(collector->projection.camera);
        camera = EzwinMatrixPosition(EzwinUnityLocalToWorld(cameraTransform));
        transform = EzwinUnityTransform((void *)actor);
    }
    if (transform) {
        snapshot->world = EzwinMatrixPosition(EzwinUnityLocalToWorld(transform));
        snapshot->esp.screen = EzwinProjectPosition(&collector->projection, snapshot->world);
        EzwinPosition delta = {snapshot->world.x - camera.x, snapshot->world.y - camera.y, snapshot->world.z - camera.z};
        snapshot->distance = length(delta);
        if (snapshot->esp.self && cameraTransform) { snapshot->world.x = camera.x; snapshot->world.z = camera.z; }
        if (health > 0) snapshot->lastAliveMilliseconds = milliseconds();
    }
    if (collector->fields & EzwinCollectFlash) {
        EzwinTraceCheckpoint(21, "collector: decoding flash fields");
        uint32_t flash = EzwinUnityDecodeValue(actor, EzwinField_ActorFlashAmount, EzwinSlot_FlashAmountDecoder);
        memcpy(&snapshot->flash, &flash, 4);
        snapshot->flashed = (EzwinUnityDecodeValue(actor, EzwinField_ActorFlashed, EzwinSlot_FlashedDecoder) & 1) != 0;
    }
    if (collector->fields & EzwinCollectScope) {
        EzwinTraceCheckpoint(22, "collector: reading scope state");
        snapshot->scoped = EzwinUnityScoped(actor);
    }
    uint64_t nowNanoseconds = uptimeNanoseconds();
    snapshot->planting = EzwinActorSoundRecent(collector->sound, actor, 5, 1200, nowNanoseconds);
    snapshot->defusing = EzwinActorSoundRecent(collector->sound, actor, 6, 1200, nowNanoseconds);
    uintptr_t owner = pointer(actor + EzwinField_ActorDrawComponent);
    // Draw callbacks receive this game component, not its visibility helper at +0x28.
    snapshot->renderer = owner;
    // Version 1.90.0 supplies a frame-based protection flag; the native sampler leaves its timer at zero.
    if (collector->fields & EzwinCollectProtection) {
        EzwinTraceCheckpoint(23, "collector: reading protection state");
        snapshot->invulnerable = EzwinUnityInvulnerable(actor);
    }
    snapshot->invulnerabilityTime = 0;
    if (collector->fields & EzwinCollectWeapon) {
        EzwinTraceCheckpoint(24, "collector: resolving weapon definition");
        snapshot->weaponID = EzwinUnityWeaponID(actor);
        snprintf(snapshot->weapon, sizeof(snapshot->weapon), "%s", EzwinWeaponName(snapshot->weaponID));
    }
    if ((collector->fields & (EzwinCollectGeometry|EzwinCollectAim)) && (snapshot->esp.eligible || snapshot->esp.self)) {
        EzwinTraceCheckpoint(25, "collector: sampling bones and visibility");
        bones(collector, snapshot, camera);
    }
    // ESP uses sampled bones even when Unity culled the renderer. A chams draw
    // history must not control whether independent overlay geometry is shown.
    snapshot->esp.skeletonSuppressed = false;
    EzwinTraceCheckpoint(26, "collector: completed");
    return snapshot;
}

