#include "features/esp/EzwinESPDraw.h"
#include <math.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

static_assert(sizeof(EzwinDrawCommand) == 56, "Native draw command size");

static void outlinedText(const EzwinESPPainter *p, EzwinPoint position,
    uint32_t color, const char *text, float size, bool icon) {
    const uint32_t outline = color & 0xff000000;
    const float offsets[8][2] = {
        {-1, 0}, {1, 0}, {0, -1}, {0, 1},
        {-1, -1}, {1, -1}, {-1, 1}, {1, 1}
    };
    for (int i = 0; i < (icon ? 4 : 8); ++i) {
        uint32_t shade = i < 4 ? outline : (((color >> 24) * 200 / 255) << 24);
        p->text(p->context, {position.x + offsets[i][0], position.y + offsets[i][1]},
            shade, text, size, icon);
    }
    p->text(p->context, position, color, text, size, icon);
}

void EzwinDrawESPCommands(const EzwinESPPainter *p, const EzwinDrawCommand *commands,
    size_t count) {
    for (size_t i = 0; i < count; ++i) {
        const EzwinDrawCommand *c = commands + i;
        EzwinPoint start = {c->x, c->y}, end = {c->right, c->bottom};
        switch (c->kind) {
            case 0:
                p->line(p->context, start, end, c->color, c->thickness);
                break;
            case 1:
                p->rectangle(p->context, start, end, c->color, 0, c->thickness, 0, false);
                break;
            case 2:
                p->rectangle(p->context, start, end, c->color, 0, 0, 0, true);
                break;
            case 3:
                p->rectangle(p->context, start, end, c->color, c->thickness, 0,
                    (int)c->flags, true);
                break;
            case 4:
                p->circle(p->context, start, c->right, c->color, c->thickness, 24, false);
                break;
            case 5:
                p->circle(p->context, start, c->right, c->color, 0, 24, true);
                break;
            case 6:
                if (c->bottom > 0) {
                    int segments = (int)fmaf(c->bottom, 24.0f, 1.5f);
                    if (segments < 3) segments = 2;
                    p->arc(p->context, start, c->right, -1.5707964f,
                        fmaf(c->bottom, 6.2831855f, -1.5707964f), segments,
                        c->color, c->thickness);
                }
                break;
            case 7:
            case 8:
            case 9: {
                bool icon = (c->flags & 1) != 0;
                float size = icon ? 8.0f : 11.0f;
                float width = c->kind == 8 ? 0 :
                    p->textWidth(p->context, c->content.text, size, icon);
                if (c->kind == 7) start.x -= width * 0.5f;
                if (c->kind == 9) start.x -= width;
                start.x = floorf(start.x);
                start.y = floorf(start.y);
                outlinedText(p, start, c->color, c->content.text, size, icon);
                break;
            }
            case 10:
                p->image(p->context, c->content.texture, start, end, c->color);
                break;
        }
    }
}

typedef struct {
    EzwinDrawCommand *commands;
    size_t count, capacity;
} CommandBuffer;

static CommandBuffer pending, displayed;
static int64_t lastPublication;
static pthread_mutex_t queueMutex = PTHREAD_MUTEX_INITIALIZER;

bool EzwinQueueESPCommand(EzwinDrawCommand command) {
    pthread_mutex_lock(&queueMutex);
    bool stored = false;
    if (pending.count < 16384) {
        if (pending.count == pending.capacity) {
            size_t capacity = pending.capacity ? pending.capacity * 2 : 1;
            EzwinDrawCommand *memory = (EzwinDrawCommand *)realloc(pending.commands,
                capacity * sizeof(EzwinDrawCommand));
            if (memory) { pending.commands = memory; pending.capacity = capacity; }
        }
        if (pending.count < pending.capacity) {
            pending.commands[pending.count++] = command;
            stored = true;
        }
    }
    pthread_mutex_unlock(&queueMutex);
    return stored;
}

void EzwinRenderESPQueue(const EzwinESPPainter *painter, int64_t nowNanoseconds) {
    pthread_mutex_lock(&queueMutex);
    if (pending.count) {
        CommandBuffer previous = displayed;
        displayed = pending;
        pending = previous;
        pending.count = 0;
        lastPublication = nowNanoseconds;
    }
    if (nowNanoseconds - lastPublication > 100999999) displayed.count = 0;
    EzwinDrawESPCommands(painter, displayed.commands, displayed.count);
    pthread_mutex_unlock(&queueMutex);
}

void EzwinClearESPQueue(void) {
    pthread_mutex_lock(&queueMutex);
    pending.count = displayed.count = 0;
    pthread_mutex_unlock(&queueMutex);
}
