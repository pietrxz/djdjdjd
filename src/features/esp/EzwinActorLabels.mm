#include "features/esp/EzwinActorCollector.h"
#include "features/items/EzwinWeaponIcons.h"
#include <math.h>
#include <stdio.h>
#pragma clang fp contract(off)

void EzwinFormatActorLabels(EzwinCollectedActor *actor, float textHeight, float flagHeight) {
    snprintf(actor->distanceText, sizeof(actor->distanceText), "[%d]", (int)actor->distance);
    snprintf(actor->joinedText, sizeof(actor->joinedText), "%s %s", actor->name, actor->distanceText);
    snprintf(actor->moneyText, sizeof(actor->moneyText), "$%d", actor->money);
    snprintf(actor->pingText, sizeof(actor->pingText), "%d ms", actor->ping);
    if (actor->flash > 0) snprintf(actor->flashText, sizeof(actor->flashText), "FLASHED %.1fs", actor->flash);
    else snprintf(actor->flashText, sizeof(actor->flashText), "FLASHED");
    if (actor->invulnerabilityTime > 0)
        snprintf(actor->invulnerabilityText, sizeof(actor->invulnerabilityText), "INVUL %.1fs", actor->invulnerabilityTime);
    else snprintf(actor->invulnerabilityText, sizeof(actor->invulnerabilityText), "INVUL");
    snprintf(actor->armorText, sizeof(actor->armorText), "%s", actor->helmet && actor->vest ? "HK" : (actor->helmet ? "K" : (actor->vest ? "H" : "")));
    EzwinESPLabelContent *labels = &actor->esp.labels;
    labels->name = actor->name; labels->distance = actor->distanceText; labels->joinedNameDistance = actor->joinedText;
    labels->weapon = actor->weapon; labels->weaponAvailable = actor->weapon[0] != 0;
    labels->money = actor->moneyText; labels->ping = actor->pingText;
    labels->flash = actor->flashText; labels->invulnerability = actor->invulnerabilityText;
    labels->armor = actor->armorText;
    // Availability is faded separately; retain text while a status fades out.
    labels->scoped = labels->planting = labels->defusing = true;
    labels->textHeight = textHeight; labels->flagHeight = flagHeight;
}


void EzwinPrepareActorLabels(EzwinCollectedActor *actor, const EzwinESPOptions *options,
    float textHeight, float flagHeight, uint64_t nanoseconds) {
    EzwinFormatActorLabels(actor, textHeight, flagHeight);
    bool available[16] = {};
    available[1] = available[2] = options->detailsStyle == 1;
    available[6] = available[7] = actor->weapon[0] != 0;
    available[8] = available[13] = true;
    available[9] = actor->vest || actor->helmet;
    available[10] = actor->scoped;
    available[11] = actor->flashed;
    available[12] = actor->invulnerable;
    available[14] = actor->planting;
    // Planting and defusing are separate sound-derived flags.
    available[15] = actor->defusing;
    for (int i = 0; i < 16; ++i) {
        float target = available[i] && options->placement.enabled[i] ? 1 : 0;
        float *alpha = actor->labelAlpha + i;
        if (*alpha < target) *alpha = fminf(*alpha + .18f, target);
        else if (*alpha > target) *alpha -= .18f;
        actor->esp.labels.alpha[i] = *alpha;
        actor->esp.labels.color[i] = options->textColor;
    }
    float seconds = (float)(nanoseconds / 1000000000) + (float)(nanoseconds % 1000000000) * 1e-9f;
    if (actor->ping > 100)
        actor->esp.labels.alpha[13] *= sinf(seconds * 6.2831855f * 1.4f) * .3f + .7f;
    if (actor->invulnerabilityTime > 0 && actor->invulnerabilityTime < 1)
        actor->esp.labels.alpha[12] *= sinf(seconds * 6.2831855f * 3) * .375f + .625f;
    actor->esp.labels.weaponWidth = 39;
    actor->esp.labels.weaponHeight = 12;
    actor->esp.labels.weaponColor = options->textColor;
    actor->esp.weaponTexture = 0;
    if (options->placement.enabled[7]) {
        float width;
        actor->esp.weaponTexture = EzwinWeaponIconTexture(actor->weapon, 12, &width);
        if (actor->esp.weaponTexture) {
            actor->esp.labels.weaponWidth = fminf(width, 40);
            if (width > 40) actor->esp.labels.weaponHeight = (40 / width) * 12;
        }
    }
}
