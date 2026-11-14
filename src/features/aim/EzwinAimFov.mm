#include "imgui.h"

// Circle geometry used by the frame renderer.
void EzwinDrawAimFovCircle(ImDrawList *drawList, float width, float height, float fov) {
    const ImVec2 center(width * 0.5f, height * 0.5f);
    const float radius = (float)((double)width * 0.25 * (double)(fov / 90.0f));
    drawList->AddCircle(center, radius, 0x96ff5b86U, 64, 2.0f);
}
