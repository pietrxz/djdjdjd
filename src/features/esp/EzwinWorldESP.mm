#include "features/esp/EzwinWorldESP.h"
#include "features/esp/EzwinESPGeometry.h"
#include <math.h>
#pragma clang fp contract(off)

static_assert(sizeof(EzwinSoundTrail) == 0x98, "Native six-point sound trail");
static_assert(sizeof(EzwinOffscreenActor) == 0x20, "Native offscreen actor state");
static unsigned actorSlot(uintptr_t actor) { return (unsigned)((actor * 0x1e3779b1ULL) >> 24) & 31; }
static EzwinSoundTrail *trail(EzwinWorldESPState *state, uintptr_t actor, EzwinPosition position) {
    EzwinSoundTrail *entry = state->trails + actorSlot(actor);
    if (entry->actor != actor) { *entry = {}; entry->actor = actor; entry->previous = position; }
    return entry;
}
static void addPoint(EzwinSoundTrail *entry, EzwinPosition position, float time, uint8_t category) {
    entry->points[entry->next] = {position, time, category, {}};
    entry->next = (entry->next + 1) % 6;
}
void EzwinRecordWorldShot(EzwinWorldESPState *state, uintptr_t actor, EzwinPosition position) {
    if (state && actor) addPoint(trail(state, actor, position), position, state->time, 1);
}

static uint32_t rgbAlpha(uint32_t color, uint32_t fallback, unsigned alpha) {
    return ((color ? color : fallback) & 0xffffff) | (alpha << 24);
}
static void soundRing(const EzwinProjection *projection, const EzwinWorldESPPainter *painter,
    EzwinPosition center, float radius, uint32_t color) {
    EzwinPoint points[28]; bool front[28]; int visible = 0;
    for (int i = 0; i < 28; ++i) {
        float angle = (float)i * (6.2831855f / 28);
        EzwinPosition screen = EzwinProjectPosition(projection,
            {center.x + radius * cosf(angle), center.y, center.z + radius * sinf(angle)});
        points[i] = {screen.x, screen.y}; front[i] = screen.z >= .001f;
        visible += front[i];
    }
    for (int i = 0; i < 28; ++i) {
        int next = (i + 1) % 28;
        if (front[i] && front[next]) painter->line(painter->context, points[i], points[next], color, 1.8f);
    }
    unsigned alpha = color >> 24;
    if (visible == 28 && alpha > 4)
        painter->polygon(painter->context, points, 28, (color & 0xffffff) | ((alpha / 5) << 24));
}

typedef struct { uintptr_t actor; float x, y, alpha, size; uint32_t color; } Arrow;
static void appendArrow(Arrow arrows[64], int *count, const EzwinOffscreenActor *entry,
    const EzwinProjection *projection, float size) {
    if (entry->alpha <= .01f || *count >= 64) return;
    EzwinPosition screen = EzwinProjectPosition(projection,entry->position);
    float x = screen.x-projection->width*.5f, y = screen.y-projection->height*.5f;
    if (screen.z < .001f) { x = -x; y = -y; }
    float length = sqrtf(y*y+x*x);
    arrows[(*count)++] = {entry->actor,length >= 1 ? x/length : 0,length >= 1 ? y/length : 1,
        entry->alpha,size,entry->color};
}
static void separateArrows(Arrow arrows[64], int count, float radius, float size) {
    if (count < 2 || radius < 1) return;
    struct Angle { int index; float wanted, placed; } angles[64], rotated[64];
    const float tau = 6.2831855f;
    for (int i = 0; i < count; ++i) {
        float angle = atan2f(arrows[i].y, arrows[i].x);
        if (angle < 0) angle += tau;
        angles[i] = {i, angle, angle};
        int j = i;
        while (j > 0 && angles[j].wanted < angles[j-1].wanted) {
            Angle previous = angles[j-1]; angles[j-1] = angles[j]; angles[j] = previous; --j;
        }
    }
    // Cut the circle at its largest gap, then solve the minimum-gap layout by pooling adjacent blocks.
    int cut = 0; float largest = -1;
    for (int i = 0; i < count; ++i) {
        int next = (i + 1) % count;
        float gap = angles[next].wanted - angles[i].wanted + (next == 0 ? tau : 0);
        if (gap > largest) { largest = gap; cut = next; }
    }
    for (int i = 0; i < count; ++i) {
        rotated[i] = angles[(cut+i)%count];
        if (i && rotated[i].wanted < rotated[i-1].wanted) rotated[i].wanted += tau;
    }
    float limit = size;
    if (count > 2) { float tangent = tanf(3.1415927f / count); limit = radius * tangent / (tangent * .68f + .84f); }
    float fitted = fminf(size, limit * .995f);
    float spacing = 2 * atan2f(fitted * .84f, radius - fitted * .68f);
    struct Block { int first, last, count; float mean; } blocks[64]; int used = 0;
    for (int i = 0; i < count; ++i) {
        blocks[used++] = {i,i,1,rotated[i].wanted-spacing*i};
        while (used > 1 && blocks[used-2].mean > blocks[used-1].mean) {
            Block *a = blocks+used-2, *b = blocks+used-1;
            a->mean = (a->mean*a->count + b->mean*b->count) / (a->count+b->count);
            a->last = b->last; a->count += b->count; --used;
        }
    }
    for (int i = 0; i < used; ++i) for (int j = blocks[i].first; j <= blocks[i].last; ++j)
        rotated[j].placed = blocks[i].mean + spacing*j;
    if (rotated[0].placed + tau - rotated[count-1].placed + 1e-5f < spacing) {
        float mean = 0;
        for (int i = 0; i < count; ++i) mean += rotated[i].wanted-spacing*i;
        for (int i = 0; i < count; ++i) rotated[i].placed = mean/count+spacing*i;
    }
    for (int i = 0; i < count; ++i) {
        Arrow *arrow = arrows+rotated[i].index;
        arrow->x = cosf(rotated[i].placed); arrow->y = sinf(rotated[i].placed); arrow->size = fitted;
    }
}

static void drawArrow(const Arrow *arrow, const EzwinProjection *projection, float radius,
    const EzwinWorldESPPainter *painter) {
    static const float shape[10][2] = {{0,1},{.84f,-.68f},{.63f,-.53125f},{.42f,-.425f},
        {.21f,-.36125f},{0,-.34f},{-.21f,-.36125f},{-.42f,-.425f},{-.63f,-.53125f},{-.84f,-.68f}};
    if (!(arrow->size > 0)) return;
    float x = radius*arrow->x + projection->width*.5f, y = radius*arrow->y + projection->height*.5f;
    EzwinPoint points[10];
    for (int i = 0; i < 10; ++i) points[i] = {
        x + arrow->size*(arrow->x*shape[i][1]-arrow->y*shape[i][0]),
        y + arrow->size*(arrow->y*shape[i][1]+arrow->x*shape[i][0])};
    uint32_t color = EzwinESPColorWithAlpha(arrow->color, arrow->alpha);
    if (color >> 24) painter->polygon(painter->context, points, 10, color);
}

static void offscreenSound(const EzwinWorldESPState *state, const Arrow *arrow,
    const EzwinProjection *projection, float radius, const EzwinWorldESPOptions *options,
    const EzwinWorldESPPainter *painter) {
    if (!options->sound || !options->offscreenSoundCircles) return;
    const EzwinSoundTrail *entry = state->trails+actorSlot(arrow->actor);
    if (entry->actor != arrow->actor) return;
    for (int i = 0; i < 6; ++i) {
        const EzwinSoundTrailPoint *point = entry->points+i;
        float age = state->time-point->time;
        if (!(point->time > 0) || age >= .65f) continue;
        bool shot = point->category == 1;
        if (shot ? !options->shots : !options->movement) continue;
        float progress = fmaxf(age/.65f,0), alpha = arrow->alpha*(1-progress)*(1-progress);
        if (alpha < .01f) continue;
        uint32_t color = rgbAlpha(shot ? options->shotColor : options->movementColor,
            shot ? 0x3c3cff : 0xffdc78, (unsigned)(alpha*255));
        float base = shot ? 12 : 8, growth = shot ? 28 : 18;
        painter->circle(painter->context, {projection->width*.5f+radius*arrow->x,
            projection->height*.5f+radius*arrow->y}, base+growth*progress, color, shot ? 2.4f : 1.6f);
    }
}

void EzwinRenderWorldESP(EzwinWorldESPState *state, const EzwinActorCollector *collector,
    const EzwinWorldESPOptions *options, const EzwinWorldESPPainter *painter, float delta) {
    if (!state || !collector || !options || !painter || !collector->projection.initialized) return;
    state->time += delta; ++state->frame;
    const EzwinProjection *projection = &collector->projection;
    if (options->sound) {
        for (int i = 0; i < 32; ++i) {
            const EzwinCollectedActor *actor = collector->actors+i;
            if (!actor->esp.actor || !actor->esp.eligible || actor->esp.self) continue;
            EzwinSoundTrail *entry = trail(state,actor->esp.actor,actor->world); entry->frame = (int)state->frame;
            if (actor->esp.health <= 0) continue;
            float x = actor->world.x-entry->previous.x, z = actor->world.z-entry->previous.z;
            float distance = sqrtf(z*z+x*x);
            if (distance < 6) { entry->distance += distance;
                if (entry->distance >= 1.4f) { entry->distance = 0; addPoint(entry,actor->world,state->time,0); }
            }
            entry->previous = actor->world;
        }
        for (int i = 0; i < 32; ++i) {
            EzwinSoundTrail *entry = state->trails+i; bool alive = false;
            if (!entry->actor) continue;
            for (int j = 0; j < 6; ++j) {
                EzwinSoundTrailPoint *point = entry->points+j;
                if (!(point->time > 0)) continue;
                float age = state->time-point->time;
                if (age >= .65f) { point->time = 0; continue; }
                alive = true;
                if (point->category == 1 ? !options->shots : !options->movement) continue;
                float progress = age/.65f, radius = fmaxf(options->soundScale,.2f)*progress;
                float fade = (1-progress)*(1-progress);
                if (radius <= .01f || fade <= .01f) continue;
                uint32_t color = rgbAlpha(point->category == 1 ? options->shotColor : options->movementColor,
                    0xffffff, (unsigned)(220*fade));
                soundRing(projection,painter,point->position,radius,color);
            }
            if (!alive && entry->frame != (int)state->frame) entry->actor = 0;
        }
    }
    if (!options->arrows) return;
    float size = fminf(options->arrowSize,24), blend = fminf(delta*8,1);
    float maximum = fmaxf(fminf(projection->width,projection->height)*.5f-size-8,80);
    float radius = fminf(options->arrowRadius,maximum);
    if (!state->cachedArrowVisible) state->cachedArrowVisible = 0xb45050ff;
    if (!state->cachedArrowHidden) state->cachedArrowHidden = 0xb45050ff;
    if (options->arrowVisible) state->cachedArrowVisible = rgbAlpha(options->arrowVisible,0,180);
    if (options->arrowHidden) state->cachedArrowHidden = rgbAlpha(options->arrowHidden,0,180);
    Arrow arrows[64]; int count = 0;
    for (int i = 0; i < 32; ++i) {
        const EzwinCollectedActor *actor = collector->actors+i;
        if (!actor->esp.actor || !actor->esp.eligible || actor->esp.health <= 0) continue;
        EzwinOffscreenActor *entry = state->arrows+actorSlot(actor->esp.actor);
        if (entry->actor != actor->esp.actor) { *entry = {}; entry->actor = actor->esp.actor; }
        EzwinPosition point = actor->worldBones[0];
        if (point.x == 0 && point.y == 0 && point.z == 0) point = {actor->world.x,actor->world.y+.9f,actor->world.z};
        else point = {(point.x+actor->world.x)*.5f,(point.y+actor->world.y)*.5f,(point.z+actor->world.z)*.5f};
        EzwinPosition screen = EzwinProjectPosition(projection,point);
        float target = screen.z >= .001f && screen.x >= 1 && screen.x <= projection->width-1 &&
            screen.y >= 1 && screen.y <= projection->height-1 ? 0 : 1;
        entry->alpha += blend*(target-entry->alpha); entry->position = point; entry->frame = state->frame;
        entry->color = actor->esp.boneVisible[5] ? state->cachedArrowVisible : state->cachedArrowHidden;
        appendArrow(arrows,&count,entry,projection,size);
    }
    for (int i = 0; i < 32; ++i) {
        EzwinOffscreenActor *entry = state->arrows+i;
        if (!entry->actor) continue;
        if (entry->frame != state->frame) {
            entry->alpha += blend*(0-entry->alpha);
            if (entry->alpha <= .01f) { *entry = {}; continue; }
            appendArrow(arrows,&count,entry,projection,size);
        }
    }
    separateArrows(arrows,count,radius,size);
    for (int i = 0; i < count; ++i) { offscreenSound(state,arrows+i,projection,radius,options,painter);
        drawArrow(arrows+i,projection,radius,painter); }
}
