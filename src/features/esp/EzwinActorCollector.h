#pragma once
#include "features/esp/EzwinESP.h"
#include "unity/EzwinProjection.h"
#include "features/chams/EzwinPlayerChams.h"
#include "features/audio/EzwinActorSound.h"

typedef struct {
    EzwinESPActor esp;
    EzwinPosition world, worldBones[11];
    uintptr_t renderer;
    int team, money, ping, statistics[3], weaponID;
    bool helmet, vest, scoped, flashed, invulnerable, planting, defusing;
    bool statusActive, previousInvulnerability;
    float distance, flash, invulnerabilityTime, statusDuration;
    uint64_t lastAliveMilliseconds, invulnerabilityCounter;
    double invulnerabilityStarted;
    int32_t sampledFrame;
    uint16_t sampledBones;
    float labelAlpha[16];
    char name[64], weapon[64], distanceText[32], joinedText[112];
    char moneyText[32], pingText[32], flashText[32], invulnerabilityText[32], armorText[32];
} EzwinCollectedActor;

enum EzwinActorFields : unsigned {
    EzwinCollectName = 1, EzwinCollectStatistics = 2, EzwinCollectArmor = 4,
    EzwinCollectFlash = 8, EzwinCollectScope = 16, EzwinCollectProtection = 32,
    EzwinCollectWeapon = 64, EzwinCollectGeometry = 128, EzwinCollectPosition = 256,
    EzwinCollectVisibility = 512, EzwinCollectAllFields = 1023, EzwinCollectAim = 1024
};

typedef struct {
    EzwinProjection projection;
    EzwinPlayerChamsState *rendererHistory;
    const EzwinActorSoundState *sound;
    uintptr_t localActor;
    int localTeam, layerMask;
    int32_t frame;
    uint64_t fadeTime;
    bool allBoneVisibility, sampleHitboxes;
    unsigned fields;
    int aimBone;
    EzwinCollectedActor actors[32];
} EzwinActorCollector;

void EzwinAdvanceActorFades(EzwinActorCollector *collector, uint64_t nanoseconds);
EzwinCollectedActor *EzwinCollectActor(EzwinActorCollector *collector, uintptr_t actor);
void EzwinFormatActorLabels(EzwinCollectedActor *actor, float textHeight, float flagHeight);
void EzwinPrepareActorLabels(EzwinCollectedActor *actor, const EzwinESPOptions *options,
    float textHeight, float flagHeight, uint64_t nanoseconds);
