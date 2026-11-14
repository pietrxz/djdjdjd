#include "features/esp/EzwinESPDraw.h"
#include "core/EzwinRuntime.h"
#include "imgui.h"

typedef struct { ImDrawList *list; ImFont *font, *icons; } ImGuiPainter;
static ImVec2 point(EzwinPoint p) { return {p.x, p.y}; }
static void line(void *context, EzwinPoint a, EzwinPoint b, uint32_t color, float thickness) {
    ((ImGuiPainter *)context)->list->AddLine(point(a), point(b), color, thickness);
}
static void rectangle(void *context, EzwinPoint a, EzwinPoint b, uint32_t color,
    float rounding, float thickness, int flags, bool filled) {
    ImDrawList *list = ((ImGuiPainter *)context)->list;
    if (filled) list->AddRectFilled(point(a), point(b), color, rounding, flags);
    else list->AddRect(point(a), point(b), color, rounding, flags, thickness);
}
static void circle(void *context, EzwinPoint center, float radius, uint32_t color,
    float thickness, int segments, bool filled) {
    ImDrawList *list = ((ImGuiPainter *)context)->list;
    if (filled) list->AddCircleFilled(point(center), radius, color, segments);
    else list->AddCircle(point(center), radius, color, segments, thickness);
}
static void arc(void *context, EzwinPoint center, float radius, float from, float to,
    int segments, uint32_t color, float thickness) {
    ImDrawList *list = ((ImGuiPainter *)context)->list;
    list->PathArcTo(point(center), radius, from, to, segments);
    list->PathStroke(color, 0, thickness);
}
static ImFont *fontFor(ImGuiPainter *p, bool icon) {
    ImFont *font = icon ? p->icons : p->font;
    return font ? font : ImGui::GetFont();
}
static float textWidth(void *context, const char *text, float size, bool icon) {
    ImGuiPainter *p = (ImGuiPainter *)context;
    return fontFor(p, icon)->CalcTextSizeA(size, 3.4028235e+38f, 0, text).x;
}
static void text(void *context, EzwinPoint position, uint32_t color,
    const char *value, float size, bool icon) {
    ImGuiPainter *p = (ImGuiPainter *)context;
    p->list->AddText(fontFor(p, icon), size, point(position), color, value);
}
static void image(void *context, uintptr_t texture, EzwinPoint a, EzwinPoint b,
    uint32_t color) {
    ((ImGuiPainter *)context)->list->AddImage((ImTextureID)texture, point(a), point(b),
        {0, 0}, {1, 1}, color);
}
static void polygon(void *context, const EzwinPoint *points, int count, uint32_t color) {
    ImDrawList *list = ((ImGuiPainter *)context)->list;
    if (count == 10) {
        // The arrow's curved base is concave; its tip sees every base segment.
        // Write one shared mesh so translucent triangles have no antialiased internal seams.
        list->PrimReserve((count - 2) * 3, count);
        ImDrawIdx first = (ImDrawIdx)list->_VtxCurrentIdx;
        for (int i = 1; i + 1 < count; ++i) {
            list->PrimWriteIdx(first); list->PrimWriteIdx((ImDrawIdx)(first + i));
            list->PrimWriteIdx((ImDrawIdx)(first + i + 1));
        }
        ImVec2 uv = ImGui::GetIO().Fonts->TexUvWhitePixel;
        for (int i = 0; i < count; ++i) list->PrimWriteVtx(point(points[i]), uv, color);
    } else {
        ImVec2 vertices[28];
        if (count > 28) return;
        for (int i = 0; i < count; ++i) vertices[i] = point(points[i]);
        list->AddConvexPolyFilled(vertices, count, color);
    }
}
static void worldCircle(void *context, EzwinPoint center, float radius, uint32_t color, float thickness) {
    circle(context, center, radius, color, thickness, 24, false);
}
void EzwinRenderESPWithImGui(ImDrawList *drawList, ImFont *font, ImFont *iconFont,
    int64_t nowNanoseconds) {
    if (!drawList) return;
    ImGuiPainter context = {drawList, font, iconFont};
    EzwinESPPainter painter = {&context, line, rectangle, circle, arc, textWidth, text, image};
    EzwinRenderESPQueue(&painter, nowNanoseconds);
    EzwinWorldESPPainter world = {&context, line, polygon, worldCircle};
    EzwinRenderRuntimeWorldESP(&world, ImGui::GetIO().DeltaTime);
    EzwinRuntimeOptions options; EzwinGetRuntimeOptions(&options);
    if(options.aim.selection.enabled && options.aim.showFOV && options.aim.selection.fov > 0) {
        float width=options.esp.screenWidth,height=options.esp.screenHeight;
        drawList->AddCircle({width*.5f,height*.5f},(options.aim.selection.fov/90)*width*.25f,
            options.esp.color,96,1);
    }
}
