#pragma once
#include "features/esp/EzwinActorCollector.h"
#include "features/skins/EzwinSkinChanger.h"
#include "features/esp/EzwinWorldESP.h"
#include "features/aim/EzwinAimController.h"
#include "features/items/EzwinItemESP.h"

typedef struct {
    EzwinESPOptions esp;
    bool playerChams, firstPersonChams, rainbow, skinChanger;
    uint32_t visibleColor, hiddenColor;
    EzwinPlayerChamsOptions player;
    EzwinChamsGroup firstPerson[2];
    float viewStretch, textHeight, flagHeight;
    int visibilityMask;
    EzwinWorldESPOptions worldESP;
    bool selfChams;
    EzwinAimSettings aim;
    EzwinItemOptions items;
} EzwinRuntimeOptions;

void EzwinSetRuntimeOptions(const EzwinRuntimeOptions *options);
bool EzwinGetRuntimeOptions(EzwinRuntimeOptions *options);
EzwinSkinChanger *EzwinRuntimeSkinChanger(void);
void EzwinStartRuntime(void);
NSDictionary *EzwinRuntimeStatus(void);
void EzwinRenderRuntimeWorldESP(const EzwinWorldESPPainter *painter, float delta);
