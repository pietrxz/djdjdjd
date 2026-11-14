#include "features/esp/EzwinESPGeometry.h"
#include <math.h>
#include <stdio.h>
#pragma clang fp contract(off)

static_assert(sizeof(EzwinESPLabel) == 72, "Native ESP label size");

uint32_t EzwinESPColorWithAlpha(uint32_t color, float alpha) {
    if (alpha < 1.0f) {
        if (alpha <= 0.0f) return 0;
        uint32_t faded = (uint32_t)(alpha * (float)(color >> 24));
        return (color & 0xffffff) | (faded << 24);
    }
    return color;
}

EzwinESPBox EzwinESPPlayerBox(float screenX, float screenY, float headY, float headDepth) {
    float top = headDepth > 0.01f ? headY : screenY - 100.0f;
    float span = screenY - top;
    if (span < 30.0f) span = 30.0f;
    top = fmaf(span, -0.18f, top);
    float height = fmaf(span, 0.04f, screenY) - top;
    float width = height * 0.5f;
    return {fmaf(width, -0.5f, screenX), top, width, height, 1.0f};
}

static bool isBar(int element) { return element == 3 || element == 4; }

static EzwinDrawCommand rectangle(int kind, float x, float y, float right,
    float bottom, uint32_t color, float thickness) {
    EzwinDrawCommand c = {};
    c.kind = kind;
    c.x = x; c.y = y; c.right = right; c.bottom = bottom;
    c.color = color; c.thickness = thickness;
    return c;
}

int EzwinESPBarCommands(EzwinESPBox box, float fraction, int element,
    const EzwinESPPlacement *placement, uint32_t foreground, uint32_t background,
    EzwinDrawCommand commands[3]) {
    int side = placement->position[element];
    float offset = 0;
    for (int i = 0; i < element; ++i) {
        if (isBar(i) && placement->enabled[i] && placement->position[i] == side) offset += 5.0f;
    }
    float left, top, right, bottom, extent;
    bool vertical = side == 2 || side == 3;
    if (vertical) {
        left = side == 2 ? ((box.x - 2.0f) - 3.0f) - offset :
            offset + ((box.x + box.width) + 2.0f);
        top = box.y - 1.0f;
        bottom = (box.y + box.height) + 1.0f;
        right = left + 3.0f;
        extent = bottom - top;
    } else {
        top = side == 0 ? ((box.y - 2.0f) - 3.0f) - offset :
            offset + ((box.y + box.height) + 2.0f);
        left = box.x - 1.0f;
        right = (box.x + box.width) + 1.0f;
        bottom = top + 3.0f;
        extent = right - left;
    }
    if (extent < 4.0f) return 0;
    int count = 0;
    commands[count++] = rectangle(2, left, top, right, bottom, background, 0);
    float fill = fminf(fmaxf(fraction, 0.0f), 1.0f) * extent;
    if (fill >= 1.0f) {
        commands[count++] = vertical ? rectangle(2, left, bottom - fill, right, bottom, foreground, 0) :
            rectangle(2, left, top, left + fill, bottom, foreground, 0);
    }
    uint32_t outline = EzwinESPColorWithAlpha(0xff000000, box.alpha);
    commands[count++] = rectangle(1, left, top, right, bottom, outline, 1.0f);
    return count;
}

static float barReservation(int position, const EzwinESPPlacement *placement) {
    static const unsigned masks[4] = {0x31, 0xc2, 0x54, 0xa8};
    float offset = 0;
    for (int i = 0; i < 16; ++i) {
        if (!isBar(i) || !placement->enabled[i]) continue;
        int side = placement->position[i];
        if (side >= 0 && side < 4 && (masks[side] & (1U << position))) offset += 5.0f;
    }
    return offset;
}

void EzwinLayoutESPLabels(EzwinESPBox box, EzwinESPLabel *labels, int count,
    const EzwinESPPlacement *placement) {
    float total[8] = {}, used[8] = {};
    int indices[8] = {};
    for (int i = 0; i < count; ++i) {
        EzwinESPLabel *label = labels + i;
        if (label->active) total[label->position] += label->spacing + 2.0f;
    }
    for (int i = 0; i < 8; ++i) if (total[i] > 0) total[i] -= 2.0f;
    float right = box.x + box.width + 6.0f;
    float bottom = box.y + box.height;
    for (int i = 0; i < count; ++i) {
        EzwinESPLabel *label = labels + i;
        if (!label->active) continue;
        int position = label->position;
        label->positionIndex = indices[position]++;
        float reserve = barReservation(position, placement);
        if (position == 2 || position == 3) {
            label->x = position == 2 ? (box.x - 6.0f) - reserve : right + reserve;
            label->y = fmaf(box.height, 0.5f, box.y) - total[position] * 0.5f + used[position];
            label->alignment = position == 2 ? 2 : 0;
        } else {
            switch (position) {
                case 0:
                    label->x = fmaf(box.width, 0.5f, box.x);
                    label->y = (((box.y - 6.0f) - reserve) - label->spacing) - used[position];
                    label->alignment = 1;
                    break;
                case 1:
                    label->x = fmaf(box.width, 0.5f, box.x);
                    label->y = used[position] + bottom + 6.0f + reserve;
                    label->alignment = 1;
                    break;
                case 4:
                case 6:
                    label->x = (box.x - 6.0f) - reserve;
                    label->y = position == 4 ? used[position] + box.y :
                        (bottom - label->spacing) - used[position];
                    label->alignment = 2;
                    break;
                default:
                    label->x = right + reserve;
                    label->y = position == 5 ? used[position] + box.y :
                        (bottom - label->spacing) - used[position];
                    label->alignment = 0;
                    break;
            }
        }
        used[position] += label->spacing + 2.0f;
    }
}

void EzwinQueueESPLabels(const EzwinESPLabel *labels, int count, uintptr_t weaponTexture,
    float actorAlpha, const float elementAlpha[16]) {
    for (int i = 0; i < count; ++i) {
        const EzwinESPLabel *label = labels + i;
        if (!label->active) continue;
        EzwinDrawCommand command = {};
        command.x = label->x; command.y = label->y;
        command.color = EzwinESPColorWithAlpha(label->color, actorAlpha * elementAlpha[label->id]);
        if (label->kind == 2) {
            if (!weaponTexture) continue;
            float left = label->x;
            float right = left + label->width;
            if (label->alignment == 1) {
                left = label->x - label->width * 0.5f;
                right = label->x + label->width * 0.5f;
            } else if (label->alignment == 2) {
                left = label->x - label->width;
                right = label->x;
            }
            command.kind = 10;
            command.x = left; command.right = right;
            command.bottom = label->y + label->height;
            command.content.texture = weaponTexture;
        } else {
            command.kind = label->alignment == 1 ? 7 : label->alignment == 2 ? 9 : 8;
            command.flags = label->id > 7;
            snprintf(command.content.text, sizeof(command.content.text), "%s", label->text);
        }
        EzwinQueueESPCommand(command);
    }
}
