#pragma once
#include <stdint.h>
#include <stddef.h>

typedef struct { float x, y; } EzwinPoint;
typedef struct {
    int kind;
    float x, y, right, bottom;
    uint32_t color;
    float thickness;
    uint32_t flags;
    union { char text[24]; uintptr_t texture; } content;
} EzwinDrawCommand;

typedef struct {
    void *context;
    void (*line)(void *, EzwinPoint, EzwinPoint, uint32_t, float);
    void (*rectangle)(void *, EzwinPoint, EzwinPoint, uint32_t, float, float, int, bool);
    void (*circle)(void *, EzwinPoint, float, uint32_t, float, int, bool);
    void (*arc)(void *, EzwinPoint, float, float, float, int, uint32_t, float);
    float (*textWidth)(void *, const char *, float, bool);
    void (*text)(void *, EzwinPoint, uint32_t, const char *, float, bool);
    void (*image)(void *, uintptr_t, EzwinPoint, EzwinPoint, uint32_t);
} EzwinESPPainter;

#ifdef __cplusplus
extern "C" {
#endif
void EzwinDrawESPCommands(const EzwinESPPainter *painter,
    const EzwinDrawCommand *commands, size_t count);
bool EzwinQueueESPCommand(EzwinDrawCommand command);
void EzwinRenderESPQueue(const EzwinESPPainter *painter, int64_t nowNanoseconds);
void EzwinClearESPQueue(void);
#ifdef __cplusplus
}
#endif

struct ImDrawList;
struct ImFont;
void EzwinRenderESPWithImGui(ImDrawList *drawList, ImFont *font, ImFont *iconFont,
    int64_t nowNanoseconds);
