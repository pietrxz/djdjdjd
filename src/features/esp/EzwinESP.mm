#include "features/esp/EzwinESP.h"
#include <math.h>
#include <stdio.h>
#include <string.h>
#pragma clang fp contract(off)

static void line(float x, float y, float right, float bottom, uint32_t color, bool outline) {
    EzwinDrawCommand command = {};
    command.x = x; command.y = y; command.right = right; command.bottom = bottom;
    if (outline) {
        command.color = color & 0xff000000;
        command.thickness = 2;
        EzwinQueueESPCommand(command);
    }
    command.color = color;
    command.thickness = 1;
    EzwinQueueESPCommand(command);
}

static void rectangle(EzwinESPBox box, uint32_t color, float thickness, float padding) {
    EzwinDrawCommand command = {};
    command.kind = 1;
    command.x = box.x - padding;
    command.y = box.y - padding;
    command.right = box.x + box.width + padding;
    command.bottom = box.y + box.height + padding;
    command.color = color; command.thickness = thickness;
    EzwinQueueESPCommand(command);
}

static void filled(float x, float y, float right, float bottom, uint32_t color,
    float rounding, uint32_t corners) {
    EzwinDrawCommand command = {};
    command.kind = 3;
    command.x = x; command.y = y; command.right = right; command.bottom = bottom;
    command.color = color; command.thickness = rounding; command.flags = corners;
    EzwinQueueESPCommand(command);
}

static void text(float x, float y, uint32_t color, const char *value, bool centered) {
    EzwinDrawCommand command = {};
    command.kind = centered ? 7 : 8;
    command.x = x; command.y = y; command.color = color;
    snprintf(command.content.text, sizeof(command.content.text), "%s", value);
    EzwinQueueESPCommand(command);
}

static void circle(EzwinPosition center, float radius, uint32_t color) {
    EzwinDrawCommand command = {};
    command.kind = 4;
    command.x = center.x; command.y = center.y; command.right = radius;
    command.color = color & 0xff000000; command.thickness = 2;
    EzwinQueueESPCommand(command);
    command.color = color; command.thickness = 1;
    EzwinQueueESPCommand(command);
}

static EzwinPosition ellipsePoint(const EzwinESPHitbox *box, int first, int second,
    float cosine, float sine) {
    EzwinPosition a = box->axes[first], b = box->axes[second];
    return {fmaf(b.x, sine, fmaf(a.x, cosine, box->center.x)),
            fmaf(b.y, sine, fmaf(a.y, cosine, box->center.y)),
            fmaf(b.z, sine, fmaf(a.z, cosine, box->center.z))};
}

static void hitboxes(const EzwinESPActor *actor, const EzwinESPOptions *options,
    EzwinESPProjection project, void *context) {
    if (!project) return;
    for (int bone = 0; bone < 11; ++bone) {
        const EzwinESPHitbox *box = actor->hitboxes + bone;
        if (!box->available) continue;
        uint32_t color = EzwinESPColorWithAlpha(box->visible ? options->hitboxVisible :
            options->hitboxHidden, actor->alpha);
        EzwinPosition previous[3] = {};
        for (int segment = 0; options->hitboxes && segment < 17; ++segment) {
            float angle = (float)segment * (6.2831855f / 16.0f);
            float cosine = cosf(angle), sine = sinf(angle);
            EzwinPosition point[3] = {
                project(context, ellipsePoint(box, 0, 1, cosine, sine)),
                project(context, ellipsePoint(box, 0, 2, cosine, sine)),
                project(context, ellipsePoint(box, 1, 2, cosine, sine))
            };
            if (segment) {
                for (int plane = 0; plane < 3; ++plane) {
                    if (previous[plane].z > .01f && point[plane].z > .01f) line(previous[plane].x,
                        previous[plane].y, point[plane].x, point[plane].y, color, false);
                }
            }
            for (int plane = 0; plane < 3; ++plane) previous[plane] = point[plane];
        }
        if (options->hitboxValues && actor->bones[bone].z > .01f) {
            char number[16]; snprintf(number, sizeof(number), "%.3f", box->radius);
            text(actor->bones[bone].x + 4, actor->bones[bone].y - 6,
                EzwinESPColorWithAlpha(0xff82e6ff, actor->alpha), number, true);
        }
    }
}

static bool hitboxBounds(const EzwinESPActor *actor, EzwinPosition corners[8]) {
    static const int selected[7] = {0, 1, 2, 3, 4, 5, 10};
    EzwinPosition minimum = {}, maximum = {};
    bool found = false;
    for (int i = 0; i < 7; ++i) {
        const EzwinESPHitbox *box = actor->hitboxes + selected[i];
        if (!box->available) continue;
        EzwinPosition extent = {
            (fabsf(box->axes[0].x) + fabsf(box->axes[1].x)) + fabsf(box->axes[2].x),
            (fabsf(box->axes[0].y) + fabsf(box->axes[1].y)) + fabsf(box->axes[2].y),
            (fabsf(box->axes[0].z) + fabsf(box->axes[1].z)) + fabsf(box->axes[2].z)};
        EzwinPosition low = {box->center.x - extent.x, box->center.y - extent.y, box->center.z - extent.z};
        EzwinPosition high = {box->center.x + extent.x, box->center.y + extent.y, box->center.z + extent.z};
        if (!found) { minimum = low; maximum = high; found = true; }
        else {
            minimum = {fminf(minimum.x, low.x), fminf(minimum.y, low.y), fminf(minimum.z, low.z)};
            maximum = {fmaxf(maximum.x, high.x), fmaxf(maximum.y, high.y), fmaxf(maximum.z, high.z)};
        }
    }
    if (!found) return false;
    EzwinPosition center = {(maximum.x + minimum.x) * .5f, (maximum.y + minimum.y) * .5f,
        (maximum.z + minimum.z) * .5f};
    EzwinPosition extent = {(maximum.x - minimum.x) * .5f, (maximum.y - minimum.y) * .5f,
        (maximum.z - minimum.z) * .5f};
    if (!(extent.y > .01f)) return false;
    float left = center.x - extent.x, right = center.x + extent.x;
    float top = center.y + extent.y, bottom = center.y - extent.y;
    float front = center.z - extent.z, back = center.z + extent.z;
    corners[0] = {left, top, front}; corners[1] = {right, top, front};
    corners[2] = {right, top, back}; corners[3] = {left, top, back};
    corners[4] = {left, bottom, front}; corners[5] = {right, bottom, front};
    corners[6] = {right, bottom, back}; corners[7] = {left, bottom, back};
    return true;
}

static void bounds(const EzwinESPActor *actor, uint32_t color, EzwinESPProjection project,
    void *context) {
    if (!project) return;
    EzwinPosition corners[8];
    bool found = hitboxBounds(actor, corners);
    if (!found && !actor->hasBounds) return;
    EzwinPosition projected[8];
    for (int i = 0; i < 8; ++i) {
        projected[i] = project(context, found ? corners[i] : actor->bounds[i]);
        if (projected[i].z <= .01f) return;
    }
    for (int i = 0; i < 4; ++i) {
        int next = (i + 1) & 3;
        line(projected[i].x, projected[i].y, projected[next].x, projected[next].y, color, true);
        line(projected[i + 4].x, projected[i + 4].y, projected[next + 4].x,
            projected[next + 4].y, color, true);
        line(projected[i].x, projected[i].y, projected[i + 4].x, projected[i + 4].y, color, true);
    }
}

static float projectedHeadRadius(const EzwinESPHitbox *box, float fallback,
    EzwinESPProjection project, void *context) {
    if (!box->available || !project) return fallback;
    EzwinPosition center = project(context, box->center);
    if (!(center.z > .01f)) return fallback;
    float maximum = 0;
    for (int i = 0; i < 3; ++i) {
        for (int sign = 1; sign >= -1; sign -= 2) {
            EzwinPosition axis = box->axes[i];
            EzwinPosition point = project(context, {box->center.x + axis.x * sign,
                box->center.y + axis.y * sign, box->center.z + axis.z * sign});
            if (point.z > .01f) {
                float x = point.x - center.x, y = point.y - center.y;
                maximum = fmaxf(maximum, fmaf(y, y, x * x));
            }
        }
    }
    return maximum > 0 ? sqrtf(maximum) : fallback;
}

static void skeleton(const EzwinESPActor *actor, const EzwinESPOptions *options,
    EzwinESPProjection project, void *context) {
    if (actor->skeletonSuppressed) return;
    float radius = 0;
    uint32_t headColor = EzwinESPColorWithAlpha(actor->boneVisible[10] && actor->boneVisible[5] ?
        options->skeletonVisible : options->skeletonHidden, actor->alpha);
    if (actor->bones[10].z > .01f && actor->bones[5].z > .01f) {
        float x = actor->bones[10].x - actor->bones[5].x;
        float y = actor->bones[10].y - actor->bones[5].y;
        float distance = sqrtf(x * x + y * y);
        radius = fminf(fmaxf(distance * .5f, 3.0f), 15.0f);
        if (options->skeleton && distance > 0) line(actor->bones[10].x + radius * (-x / distance),
            actor->bones[10].y + radius * (-y / distance), actor->bones[5].x,
            actor->bones[5].y, headColor, true);
    }
    static const int connections[9][2] = {{5,4},{5,7},{7,9},{5,6},{6,8},{4,2},{2,0},{4,3},{3,1}};
    for (int i = 0; options->skeleton && i < 9; ++i) {
        int first = connections[i][0], second = connections[i][1];
        if (actor->bones[first].z <= .01f || actor->bones[second].z <= .01f) continue;
        bool visible = actor->boneVisible[first] && actor->boneVisible[second];
        uint32_t color = EzwinESPColorWithAlpha(visible ? options->skeletonVisible :
            options->skeletonHidden, actor->alpha);
        line(actor->bones[first].x, actor->bones[first].y, actor->bones[second].x,
            actor->bones[second].y, color, true);
    }
    if (actor->bones[10].z > .01f && options->headCircle) {
        float headRadius = projectedHeadRadius(actor->hitboxes + 10, radius, project, context);
        if (headRadius > 0) circle(actor->bones[10], headRadius,
            EzwinESPColorWithAlpha(actor->boneVisible[10] ? options->skeletonVisible :
                options->skeletonHidden, actor->alpha));
    }
}

static EzwinPoint measure(EzwinESPTextSize textSize, void *context, const char *value) {
    if (!value || !*value) return {0, 0};
    if (textSize) return textSize(context, value, 12.0f);
    return {(float)strlen(value) * 6.5f, 12.0f};
}

static void detailsCard(const EzwinESPActor *actor, const EzwinESPOptions *options,
    EzwinESPBox box, EzwinESPTextSize textSize, void *context) {
    bool name = options->placement.enabled[1] && actor->labels.name && *actor->labels.name;
    bool distance = options->placement.enabled[2] && actor->labels.distance && *actor->labels.distance;
    bool health = options->placement.enabled[3], armor = options->placement.enabled[4];
    if (!name && !distance && !health && !armor) return;
    EzwinPoint nameSize = measure(textSize, context, name ? actor->labels.name : nullptr);
    EzwinPoint distanceSize = measure(textSize, context, distance ? actor->labels.distance : nullptr);
    float width = fmaxf(nameSize.x + distanceSize.x + (name && distance ? 6.0f : 0.0f) + 10.0f, 60.0f);
    float x = (box.x + box.width * .5f) - width * .5f;
    float y = (box.y - 16.0f) - fmaxf(box.height * .04f, 3.0f);
    float baseline = y + (16.0f - fmaxf(nameSize.y, distanceSize.y)) * .5f - 1.0f;
    filled(x, y, x + width, y + 16.0f, EzwinESPColorWithAlpha(0x9b000000, actor->alpha), 5, 0);
    uint32_t textColor = EzwinESPColorWithAlpha(options->textColor, actor->alpha);
    if (name) text(x + 5.0f, baseline, textColor, actor->labels.name, false);
    if (distance) text(x + 5.0f + (name ? nameSize.x + 6.0f : 0), baseline,
        textColor, actor->labels.distance, false);
    float innerWidth = width - 4.0f;
    uint32_t background = EzwinESPColorWithAlpha(0xff8c8c8c, actor->alpha);
    if (armor) {
        filled(x + 2, y + 1, x + width - 2, y + 3, background, 1, 0x30);
        float ratio = actor->armor > 0 && actor->maximumArmor > 0 ?
            fminf((float)actor->armor / actor->maximumArmor, 1.0f) : 0;
        if (innerWidth * ratio >= 2) filled(x + 2, y + 1, x + 2 + innerWidth * ratio, y + 3,
            EzwinESPColorWithAlpha(options->armorColor, actor->alpha), 1, ratio < .999f ? 0x10 : 0x30);
    }
    if (health) {
        filled(x + 2, y + 13, x + width - 2, y + 15, background, 1, 0xc0);
        float ratio = fminf(fmaxf((float)actor->health / 100.0f, 0.0f), 1.0f);
        if (innerWidth * ratio >= 2) filled(x + 2, y + 13, x + 2 + innerWidth * ratio, y + 15,
            EzwinESPColorWithAlpha(options->healthColor, actor->alpha), 1, ratio < .999f ? 0x40 : 0xc0);
    }
}

void EzwinRenderActorESP(const EzwinESPActor *actor, const EzwinESPOptions *options,
    EzwinESPProjection project, EzwinESPTextSize textSize, void *context) {
    if (!options->enabled || actor->alpha <= 0 || actor->screen.z <= .01f ||
        (actor->self ? !options->selfESP : !actor->eligible)) return;
    EzwinESPBox box = EzwinESPPlayerBox(actor->screen.x, actor->screen.y,
        actor->bones[10].y, actor->bones[10].z);
    box.alpha = actor->alpha;
    uint32_t color = EzwinESPColorWithAlpha(options->color, actor->alpha);
    if (options->lines) {
        float x = options->screenWidth * .5f, y = 0;
        float targetX = box.x + box.width * .5f, targetY = box.y;
        if (options->lineOrigin == 2 || options->lineOrigin == 3) {
            x = options->lineOrigin == 2 ? 0 : options->screenWidth;
            y = options->screenHeight * .5f;
            targetX = options->lineOrigin == 2 ? box.x : box.x + box.width;
            targetY = box.y + box.height * .5f;
        } else if (options->lineOrigin != 0) {
            y = options->screenHeight - .001f;
            targetY = box.y + box.height;
        }
        line(x, y, targetX, targetY, color, true);
    }
    if (options->box3D) bounds(actor, color, project, context);
    else if (options->box2D) {
        rectangle(box, EzwinESPColorWithAlpha(0xff000000, actor->alpha), 2, .5f);
        rectangle(box, color, 1, 0);
    }
    if (options->skeleton || options->headCircle) skeleton(actor, options, project, context);
    if ((options->hitboxes || options->hitboxValues) && !actor->skeletonSuppressed) {
        hitboxes(actor, options, project, context);
    }
    EzwinESPLabelContent content = actor->labels;
    EzwinESPPlacement placement = options->placement;
    if (options->detailsStyle == 0) {
        detailsCard(actor, options, box, textSize, context);
        content.name = content.distance = content.joinedNameDistance = "";
    } else {
        EzwinDrawCommand commands[3];
        uint32_t background = EzwinESPColorWithAlpha(0xff8c8c8c, actor->alpha);
        if (placement.enabled[3]) {
            int count = EzwinESPBarCommands(box, (float)actor->health / 100.0f, 3, &placement,
                EzwinESPColorWithAlpha(options->healthColor, actor->alpha), background, commands);
            for (int i = 0; i < count; ++i) EzwinQueueESPCommand(commands[i]);
        }
        if (placement.enabled[4]) {
            float ratio = actor->armor > 0 && actor->maximumArmor > 0 ?
                fminf((float)actor->armor / actor->maximumArmor, 1.0f) : 0;
            int count = EzwinESPBarCommands(box, ratio, 4, &placement,
                EzwinESPColorWithAlpha(options->armorColor, actor->alpha), background, commands);
            for (int i = 0; i < count; ++i) EzwinQueueESPCommand(commands[i]);
        }
    }
    EzwinESPLabel labels[16];
    int count = EzwinBuildESPLabels(&content, &placement, options->order, labels);
    EzwinLayoutESPLabels(box, labels, count, &placement);
    EzwinQueueESPLabels(labels, count, actor->weaponTexture, actor->alpha, content.alpha);
}
