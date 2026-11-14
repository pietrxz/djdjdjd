#include "ui/EzwinMenu.h"
#include "imgui.h"
#include <math.h>
#include <stdio.h>
#include <string.h>

static bool initialized, visible = true;
static const char *message = "Settings are saved only when you press Save.";
static NSString *const settingsKey = @"ezwin.cracked.menu.1900.v2";
static const char *labelNames[16] = {"Box", "Name", "Distance", "Health bar", "Armor bar", "Unused",
    "Weapon name", "Weapon icon", "Money", "Armor type", "Scoped", "Flashed", "Invulnerable", "Ping", "Planting", "Defusing"};
static const char *positions = "Top\0Bottom\0Left\0Right\0Top left\0Top right\0Bottom left\0Bottom right\0";

void EzwinApplyMenuStyle(void) {
    ImGui::StyleColorsDark();
    ImGuiStyle &style = ImGui::GetStyle();
    style.WindowRounding = 14; style.FrameRounding = 10;
    style.WindowPadding = ImVec2(14, 14); style.FramePadding = ImVec2(8, 7);
    style.ItemSpacing = ImVec2(10, 8); style.ScrollbarSize = 20;
    style.Colors[ImGuiCol_CheckMark] = ImVec4(.72f, .43f, 1, 1);
    style.Colors[ImGuiCol_Button] = ImVec4(.22f, .09f, .39f, 1);
    style.Colors[ImGuiCol_Header] = ImVec4(.22f, .09f, .39f, 1);
    style.Colors[ImGuiCol_WindowBg] = ImVec4(.025f, .023f, .04f, 1);
    style.Colors[ImGuiCol_ChildBg] = ImVec4(0, 0, 0, 0);
    style.Colors[ImGuiCol_FrameBg] = ImVec4(.065f, .055f, .09f, 1);
    style.Colors[ImGuiCol_Border] = ImVec4(.14f, .12f, .19f, 1);
    style.Colors[ImGuiCol_PopupBg] = ImVec4(.045f, .035f, .065f, 1);
    style.Colors[ImGuiCol_Text] = ImVec4(.94f, .93f, .97f, 1);
    style.Colors[ImGuiCol_TextDisabled] = ImVec4(.40f, .39f, .46f, 1);
    style.Colors[ImGuiCol_DragDropTarget] = ImVec4(.58f, .33f, .88f, 1);
}

EzwinRuntimeOptions EzwinDefaultMenuOptions(void) {
    EzwinRuntimeOptions value = {};
    value.visibilityMask = -1;
    value.esp.box2D = true;
    value.esp.color = value.esp.textColor = 0xfff5f5f5;
    value.esp.healthColor = value.esp.skeletonVisible = value.esp.hitboxVisible = 0xff7cdb68;
    value.esp.armorColor = 0xffffb166;
    value.esp.skeletonHidden = value.esp.hitboxHidden = 0xff7070f2;
    value.esp.placement.enabled[0] = value.esp.placement.enabled[1] = true;
    value.esp.placement.enabled[2] = value.esp.placement.enabled[3] = true;
    value.esp.placement.enabled[6] = true;
    for (int i = 0; i < 16; ++i) { value.esp.order[i] = i; value.esp.placement.position[i] = 3; }
    value.esp.placement.position[1] = 0;
    value.esp.placement.position[2] = value.esp.placement.position[6] = 1;
    value.esp.placement.position[3] = 2;
    value.esp.placement.position[4] = 1;
    value.textHeight = 13; value.flagHeight = 11;
    value.visibleColor = value.worldESP.arrowVisible = 0xff7cdb68;
    value.hiddenColor = value.worldESP.arrowHidden = 0xff7070f2;
    value.player = {false, false, 0, 1, 2, .4f, 4, .5f, 1, 1.4f};
    for(int i=0;i<2;++i) {
        value.firstPerson[i].mode=1;
        value.firstPerson[i].material={1,1,1,false,true,true,0xffefa982,0xffffffff};
    }
    value.worldESP.arrowSize = 16; value.worldESP.arrowRadius = 130; value.worldESP.soundScale = 2;
    value.worldESP.movement = value.worldESP.shots = true;
    value.worldESP.movementColor = 0xfff5f5f5; value.worldESP.shotColor = 0xff70b6ff;
    value.aim.selection.visibilityCheck = true;
    value.aim.selection.fov = 180; value.aim.selection.maxDistance = 500;
    value.items.color = 0xffffdc78;
    return value;
}

void EzwinDisableAllFeatures(void) {
    EzwinRuntimeOptions value; EzwinGetRuntimeOptions(&value);
    value.esp.enabled = value.playerChams = value.firstPersonChams = value.skinChanger = false;
    value.worldESP.arrows = value.worldESP.sound = false;
    value.selfChams = false;
    value.aim.selection.enabled = value.items.enabled = false;
    EzwinSetRuntimeOptions(&value);
}

void EzwinSaveMenuSettings(void) {
    @synchronized ([NSProcessInfo processInfo]) {
        EzwinRuntimeOptions value; EzwinGetRuntimeOptions(&value);
        value.esp.screenWidth = value.esp.screenHeight = 0;
        NSDictionary *saved = @{@"version":@2, @"options":[NSData dataWithBytes:&value length:sizeof(value)],
            @"skins":[EzwinRuntimeSkinChanger().selections copy]};
        [[NSUserDefaults standardUserDefaults] setObject:saved forKey:settingsKey];
    }
    message = "Settings saved.";
}

static bool validOptions(const EzwinRuntimeOptions *value) {
    if (value->esp.lineOrigin < 0 || value->esp.lineOrigin > 3 || value->esp.detailsStyle < 0 || value->esp.detailsStyle > 1) return false;
    for (int i = 0; i < 16; ++i)
        if (value->esp.placement.position[i] < 0 || value->esp.placement.position[i] > (i == 3 || i == 4 ? 3 : 7) ||
            value->esp.order[i] < 0 || value->esp.order[i] > 15) return false;
    return value->firstPerson[0].mode<=8&&value->firstPerson[1].mode<=8&&isfinite(value->viewStretch)&&isfinite(value->textHeight) && isfinite(value->flagHeight) &&
        value->aim.selection.targetBone < 7 && isfinite(value->aim.selection.fov) &&
        value->aim.selection.fov >= 0 && value->aim.selection.fov <= 180 &&
        isfinite(value->aim.selection.maxDistance) && value->aim.selection.maxDistance >= 0 &&
        value->aim.selection.maxDistance <= 500 && isfinite(value->aim.smoothness) &&
        value->aim.smoothness >= 0 && value->aim.smoothness <= 1;
}

bool EzwinLoadMenuSettings(void) {
    id saved = [[NSUserDefaults standardUserDefaults] objectForKey:settingsKey];
    if (![saved isKindOfClass:[NSDictionary class]] || [saved[@"version"] intValue] != 2) return false;
    NSData *data = saved[@"options"];
    if (![data isKindOfClass:[NSData class]] || data.length != sizeof(EzwinRuntimeOptions)) return false;
    EzwinRuntimeOptions value; memcpy(&value, data.bytes, sizeof(value));
    if (!validOptions(&value)) return false;
    @synchronized ([NSProcessInfo processInfo]) {
        EzwinRuntimeOptions current; EzwinGetRuntimeOptions(&current);
        value.esp.screenWidth = current.esp.screenWidth; value.esp.screenHeight = current.esp.screenHeight;
        EzwinSkinChanger *skins = EzwinRuntimeSkinChanger();
        [skins.selections removeAllObjects]; [skins setSkinID:0 forKey:@"Gloves (0)"];
        id selections = saved[@"skins"];
        if ([selections isKindOfClass:[NSDictionary class]]) for (id key in selections) {
            id skin = selections[key];
            if ([key isKindOfClass:[NSString class]] && [skin isKindOfClass:[NSNumber class]])
                [skins setSkinID:[skin intValue] forKey:key];
        }
        EzwinSetRuntimeOptions(&value);
    }
    message = "Settings loaded.";
    return true;
}

void EzwinResetMenuSettings(void) {
    @synchronized ([NSProcessInfo processInfo]) {
        EzwinRuntimeOptions current; EzwinGetRuntimeOptions(&current);
        EzwinRuntimeOptions value = EzwinDefaultMenuOptions();
        value.esp.screenWidth = current.esp.screenWidth; value.esp.screenHeight = current.esp.screenHeight;
        EzwinSetRuntimeOptions(&value);
        [EzwinRuntimeSkinChanger().selections removeAllObjects];
        [EzwinRuntimeSkinChanger() setSkinID:0 forKey:@"Gloves (0)"];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:settingsKey];
    }
    message = "Defaults restored. Features are off.";
}

void EzwinInitializeMenu(void) {
    if (initialized) return;
    initialized = true;
    EzwinRuntimeOptions value;
    if (!EzwinGetRuntimeOptions(&value)) { value = EzwinDefaultMenuOptions(); EzwinSetRuntimeOptions(&value); }
    EzwinLoadMenuSettings();
}
bool EzwinMenuVisible(void) { return visible; }
void EzwinSetMenuVisible(bool value) { visible = value; }

static void color(const char *label, uint32_t *packed) {
    float rgba[4] = {(float)(*packed & 255) / 255, (float)((*packed >> 8) & 255) / 255,
        (float)((*packed >> 16) & 255) / 255, (float)(*packed >> 24) / 255};
    if (ImGui::ColorEdit4(label, rgba, ImGuiColorEditFlags_NoInputs | ImGuiColorEditFlags_AlphaBar)) {
        *packed = 0;
        for (int i = 0; i < 4; ++i) *packed |= (uint32_t)(rgba[i] * 255 + .5f) << (i * 8);
    }
}

void EzwinAdvancedESPMenu(EzwinRuntimeOptions *value) {
    EzwinESPOptions *esp = &value->esp;
    ImGui::Checkbox("Enable ESP", &esp->enabled); ImGui::SameLine(); ImGui::Checkbox("Self ESP", &esp->selfESP);
    ImGui::Checkbox("2D box", &esp->box2D); ImGui::SameLine(); ImGui::Checkbox("3D box", &esp->box3D);
    ImGui::Checkbox("Snaplines", &esp->lines);
    ImGui::Combo("Line origin", &esp->lineOrigin, "Top\0Bottom\0Left\0Right\0");
    ImGui::Checkbox("Skeleton", &esp->skeleton); ImGui::SameLine(); ImGui::Checkbox("Head circle", &esp->headCircle);
    ImGui::Checkbox("Hitboxes", &esp->hitboxes); ImGui::SameLine(); ImGui::Checkbox("Hitbox values", &esp->hitboxValues);
    ImGui::Combo("Details style", &esp->detailsStyle, "Compact\0Placed labels\0");
    ImGui::SliderFloat("Text size", &value->textHeight, 8, 24, "%.0f");
    ImGui::SliderFloat("Flag size", &value->flagHeight, 8, 22, "%.0f");
    if (ImGui::CollapsingHeader("Labels and placement", ImGuiTreeNodeFlags_DefaultOpen)) {
        for (int i = 0; i < 16; ++i) {
            if (i == 5) continue;
            ImGui::PushID(i);
            ImGui::Checkbox(labelNames[i], &esp->placement.enabled[i]);
            if (i != 0) {
                if (ImGui::GetWindowWidth() >= 480) ImGui::SameLine();
                float controls = ImGui::GetContentRegionAvail().x;
                ImGui::SetNextItemWidth(fminf(160, controls * .6f));
                ImGui::Combo("##position", &esp->placement.position[i], (i == 3 || i == 4) ? "Top\0Bottom\0Left\0Right\0" : positions);
                ImGui::SameLine(); ImGui::SetNextItemWidth(fminf(70, controls * .3f));
                ImGui::SliderInt("##order", &esp->order[i], 0, 15);
            }
            ImGui::PopID();
        }
    }
    if (ImGui::CollapsingHeader("ESP colors")) {
        color("Geometry", &esp->color); color("Text", &esp->textColor);
        color("Health", &esp->healthColor); color("Armor", &esp->armorColor);
        color("Visible skeleton", &esp->skeletonVisible); color("Hidden skeleton", &esp->skeletonHidden);
        color("Visible hitbox", &esp->hitboxVisible); color("Hidden hitbox", &esp->hitboxHidden);
    }
}

void EzwinAdvancedWorldMenu(EzwinWorldESPOptions *value) {
    ImGui::Checkbox("Offscreen arrows", &value->arrows);
    ImGui::SliderFloat("Arrow size", &value->arrowSize, 4, 24, "%.0f");
    ImGui::SliderFloat("Arrow radius", &value->arrowRadius, 25, 400, "%.0f");
    color("Visible arrow", &value->arrowVisible); color("Hidden arrow", &value->arrowHidden);
    ImGui::Separator();
    ImGui::Checkbox("Sound ESP", &value->sound);
    ImGui::Checkbox("Movement trails", &value->movement); ImGui::Checkbox("Shot rings", &value->shots);
    ImGui::Checkbox("Offscreen sound circles", &value->offscreenSoundCircles);
    ImGui::SliderFloat("Sound scale", &value->soundScale, .2f, 8, "%.1f");
    color("Movement", &value->movementColor); color("Shots", &value->shotColor);
}

void EzwinAdvancedChamsMenu(EzwinRuntimeOptions *value) {
    ImGui::Checkbox("Player chams", &value->playerChams);
    ImGui::Checkbox("Rainbow", &value->rainbow);
    color("Visible player", &value->visibleColor); color("Hidden player", &value->hiddenColor);
    ImGui::Checkbox("Wireframe", &value->player.wireframe); ImGui::SameLine(); ImGui::Checkbox("Pulsate", &value->player.pulsate);
    ImGui::Combo("Player style", &value->player.style, "Solid\0Gradient\0Rim\0Smoke\0Hologram\0Marble\0Plasma\0");
    ImGui::SliderFloat("Flow speed", &value->player.flowSpeed, 0, 6);
    ImGui::SliderFloat("Outline exponent", &value->player.outlineExponent, .1f, 8);
    ImGui::SliderFloat("Outline inner", &value->player.outlineInner, 0, 1);
    ImGui::SliderFloat("Noise scale", &value->player.noiseScale, .1f, 40);
    ImGui::SliderFloat("Smoke drift", &value->player.smokeDrift, 0, 5);
    ImGui::SliderFloat("Smoke density", &value->player.smokeDensity, .1f, 5);
    ImGui::SliderFloat("Smoke rim boost", &value->player.smokeRimBoost, .1f, 5);

}

void EzwinAdvancedSkinsMenu(EzwinRuntimeOptions *value) {
    static int selectedWeapon, selectedModel, weaponCount, weapons[64];
    static char search[96];
    ImGui::Checkbox("Skin changer", &value->skinChanger);
    if (!weaponCount) {
        weapons[weaponCount++] = -1;
        for (size_t i = 0; i < EzwinSkinCatalogCount; ++i) {
            int weapon = EzwinSkinCatalog[i].weaponDefID; bool found = false;
            for (int j = 0; j < weaponCount; ++j) found |= weapons[j] == weapon;
            if (!found && weaponCount < 64) weapons[weaponCount++] = weapon;
        }
    }
    const char *title = selectedWeapon == 0 ? "All weapons" : EzwinSkinKey(weapons[selectedWeapon]).UTF8String;
    if (ImGui::BeginCombo("Weapon", title ?: "Unknown")) {
        for (int i = 0; i < weaponCount; ++i) {
            const char *name = i == 0 ? "All weapons" : EzwinSkinKey(weapons[i]).UTF8String;
            if (ImGui::Selectable(name ?: "Unknown", i == selectedWeapon)) { selectedWeapon = i; selectedModel = 0; }
        }
        ImGui::EndCombo();
    }
    int models[64] = {}, modelCount = 1, weapon = weapons[selectedWeapon];
    for (size_t i = 0; i < EzwinSkinCatalogCount; ++i) {
        const EzwinSkin *skin = EzwinSkinCatalog + i;
        if (weapon != -1 && skin->weaponDefID != weapon) continue;
        bool found = false;
        for (int j = 0; j < modelCount; ++j) found |= models[j] == skin->modelDefID;
        if (!found && modelCount < 64) models[modelCount++] = skin->modelDefID;
    }
    char modelTitle[32]; snprintf(modelTitle, sizeof(modelTitle), selectedModel ? "Model %d" : "All models", selectedModel);
    if (ImGui::BeginCombo("Model", modelTitle)) {
        for (int i = 0; i < modelCount; ++i) {
            char name[32]; snprintf(name, sizeof(name), models[i] ? "Model %d" : "All models", models[i]);
            if (ImGui::Selectable(name, selectedModel == models[i])) selectedModel = models[i];
        }
        ImGui::EndCombo();
    }
    ImGui::InputText("Search skins", search, sizeof(search));
    @synchronized ([NSProcessInfo processInfo]) {
        EzwinSkinChanger *changer = EzwinRuntimeSkinChanger();
        if (ImGui::Button("Clear selections")) {
            for (NSString *key in [changer.selections.allKeys copy]) [changer setSkinID:0 forKey:key];
        }
        ImGui::SameLine(); ImGui::Text("%lu selected", (unsigned long)changer.selections.count);
        static NSArray<NSValue *> *filtered;
        static int lastWeapon = -2, lastModel = -2;
        static char lastSearch[96];
        if (!filtered || weapon != lastWeapon || selectedModel != lastModel || strcmp(search, lastSearch)) {
            NSMutableArray<NSValue *> *rows = [NSMutableArray array];
            for (NSValue *entry in [changer skinsForWeapon:weapon model:selectedModel query:[NSString stringWithUTF8String:search]]) {
                const EzwinSkin *skin = (const EzwinSkin *)entry.pointerValue;
                if ((weapon == -1 || skin->weaponDefID == weapon) && (!selectedModel || skin->modelDefID == selectedModel))
                    [rows addObject:entry];
            }
            filtered = [rows copy]; lastWeapon = weapon; lastModel = selectedModel;
            memcpy(lastSearch, search, sizeof(search));
        }
        ImGui::BeginChild("skin-list", ImVec2(0, 0), true);
        ImGuiListClipper clipper; clipper.Begin((int)filtered.count);
        while (clipper.Step()) for (int i = clipper.DisplayStart; i < clipper.DisplayEnd; ++i) {
            const EzwinSkin *skin = (const EzwinSkin *)filtered[i].pointerValue;
            NSString *key = EzwinSkinKey(skin->weaponDefID);
            ImGui::PushID((int)(skin - EzwinSkinCatalog));
            char row[192]; snprintf(row, sizeof(row), "%s  |  %s  #%d", skin->name, key.UTF8String ?: "Unknown", skin->skinID);
            if (ImGui::Selectable(row, changer.selections[key].intValue == skin->skinID)) [changer toggleSkin:skin];
            ImGui::PopID();
        }
        ImGui::EndChild();
    }
}

