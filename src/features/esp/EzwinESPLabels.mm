#include "features/esp/EzwinESPGeometry.h"

static_assert(sizeof(EzwinESPLabelContent) == 232, "Native label content size");

static bool hasText(const char *text) { return text && *text; }

int EzwinBuildESPLabels(const EzwinESPLabelContent *c, const EzwinESPPlacement *p,
    const int order[16], EzwinESPLabel labels[16]) {
    static const int kinds[16] = {0, 1, 1, 3, 3, 4, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1};
    bool joined = p->enabled[1] && p->enabled[2] && p->position[1] < 2 &&
        p->position[1] == p->position[2] && hasText(c->name) && c->distance && c->joinedNameDistance;
    int joinedID = order[2] < order[1] ? 2 : 1;
    int count = 0;
    for (int id = 0; id < 16; ++id) {
        if ((kinds[id] != 1 && kinds[id] != 2) || !p->enabled[id] || !(c->alpha[id] > 0.01f)) continue;
        if (joined && (id == 1 || id == 2) && id != joinedID) continue;
        const char *text = nullptr;
        float height = id < 8 ? c->textHeight : c->flagHeight;
        switch (id) {
            case 1: text = hasText(c->name) ? c->name : nullptr; break;
            case 2: text = c->distance; break;
            case 6:
            case 7: text = c->weaponAvailable && hasText(c->weapon) ? c->weapon : nullptr; break;
            case 8: text = hasText(c->money) ? c->money : nullptr; break;
            case 9: text = hasText(c->armor) ? c->armor : nullptr; break;
            case 10: text = c->scoped ? "SCOPED" : nullptr; break;
            case 11: text = hasText(c->flash) ? c->flash : nullptr; break;
            case 12: text = hasText(c->invulnerability) ? c->invulnerability : nullptr; break;
            case 13: text = hasText(c->ping) ? c->ping : nullptr; break;
            case 14: text = c->planting ? "PLANTING" : nullptr; break;
            case 15: text = c->defusing ? "DEFUSING" : nullptr; break;
        }
        if (!text) continue;
        EzwinESPLabel label = {};
        label.id = id;
        label.joinedElement = -1;
        label.order = order[id];
        label.kind = kinds[id];
        label.position = p->position[id];
        label.active = true;
        label.color = c->color[id];
        label.text = text;
        label.spacing = height;
        if (id == 7) {
            label.width = c->weaponWidth;
            label.height = label.spacing = c->weaponHeight;
            label.color = c->weaponColor;
        }
        if (joined && id == joinedID) {
            label.text = c->joinedNameDistance;
            label.joinedElement = id == 1 ? 2 : 1;
        }
        int index = count++;
        while (index > 0 && labels[index - 1].order > label.order) {
            labels[index] = labels[index - 1];
            --index;
        }
        labels[index] = label;
    }
    return count;
}
