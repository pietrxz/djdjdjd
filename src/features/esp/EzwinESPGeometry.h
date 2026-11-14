#pragma once
#include "features/esp/EzwinESPDraw.h"

typedef struct { float x, y, width, height, alpha; } EzwinESPBox;
typedef struct {
    int position[16];
    bool enabled[16];
} EzwinESPPlacement;

typedef struct {
    int id, joinedElement, order, kind, position;
    bool active;
    uint8_t padding[3];
    uint32_t color, reserved;
    const char *text;
    float width, height, spacing;
    int positionIndex;
    float x, y;
    int alignment;
    uint32_t trailing;
} EzwinESPLabel;

typedef struct {
    const char *name, *distance, *joinedNameDistance, *weapon;
    bool weaponAvailable;
    uint8_t padding[7];
    const char *money, *armor, *flash, *invulnerability, *ping;
    bool scoped, planting, defusing;
    uint8_t padding2;
    float textHeight, flagHeight, weaponWidth, weaponHeight;
    uint32_t color[16];
    float alpha[16];
    uint32_t weaponColor;
} EzwinESPLabelContent;

#ifdef __cplusplus
extern "C" {
#endif
uint32_t EzwinESPColorWithAlpha(uint32_t color, float alpha);
EzwinESPBox EzwinESPPlayerBox(float screenX, float screenY, float headY, float headDepth);
int EzwinESPBarCommands(EzwinESPBox box, float fraction, int element,
    const EzwinESPPlacement *placement, uint32_t foreground, uint32_t background,
    EzwinDrawCommand commands[3]);
void EzwinLayoutESPLabels(EzwinESPBox box, EzwinESPLabel *labels, int count,
    const EzwinESPPlacement *placement);
int EzwinBuildESPLabels(const EzwinESPLabelContent *content,
    const EzwinESPPlacement *placement, const int order[16], EzwinESPLabel labels[16]);
void EzwinQueueESPLabels(const EzwinESPLabel *labels, int count, uintptr_t weaponTexture,
    float actorAlpha, const float elementAlpha[16]);
#ifdef __cplusplus
}
#endif
