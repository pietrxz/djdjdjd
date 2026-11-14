#include "ui/EzwinMenu.h"
#include "imgui.h"
#include "imgui_internal.h"
#include <math.h>
#include <stdio.h>
#include <string.h>

void EzwinAdvancedESPMenu(EzwinRuntimeOptions *);
void EzwinAdvancedWorldMenu(EzwinWorldESPOptions *);
void EzwinAdvancedChamsMenu(EzwinRuntimeOptions *);
void EzwinAdvancedSkinsMenu(EzwinRuntimeOptions *);

static float unit = 1;
static int page;
static const char *pages[] = {"Visuals", "World", "Aimbot", "Skins", "Settings"};
static constexpr int pageCount=sizeof(pages)/sizeof(pages[0]);
static const int pageIcons[]={0,1,2,5,7};
static const ImU32 white = IM_COL32(238,236,245,255), muted = IM_COL32(112,108,127,255);
static const ImU32 purple = IM_COL32(148,85,224,255), border = IM_COL32(43,35,57,255);
static const ImU32 panel = IM_COL32(19,16,27,255);

#ifdef EZWIN_MENU_TESTING
struct MenuItem { char name[96]; ImVec2 a, b; };
static MenuItem items[192];
static int itemCount;
extern "C" bool EzwinMenuTestRect(const char *name, float *bounds) {
    for (int i = 0; i < itemCount; ++i) if (!strcmp(items[i].name, name)) {
        bounds[0] = items[i].a.x; bounds[1] = items[i].a.y;
        bounds[2] = items[i].b.x; bounds[3] = items[i].b.y; return true;
    }
    return false;
}
extern "C" void EzwinMenuTestSelectPage(int selected) { if(selected>=0 && selected<pageCount)page=selected; }
#endif
static void remember(const char *name) {
#ifdef EZWIN_MENU_TESTING
    if (itemCount == 192) return;
    MenuItem *item = items + itemCount++;
    snprintf(item->name, sizeof(item->name), "%s", name);
    item->a = ImGui::GetItemRectMin(); item->b = ImGui::GetItemRectMax();
#else
    (void)name;
#endif
}
static ImVec2 point(ImVec2 p, float x, float y) { return ImVec2(p.x + x * unit, p.y + y * unit); }
static void label(ImVec2 p, const char *text, ImU32 color = white, float size = 20) {
    const char *end = strstr(text, "##");
    ImGui::GetWindowDrawList()->AddText(ImGui::GetFont(), size * unit, p, color, text, end);
}
static void rightLabel(ImVec2 p, float width, const char *text, ImU32 color = white, float size = 19) {
    ImVec2 measured = ImGui::GetFont()->CalcTextSizeA(size * unit, FLT_MAX, 0, text);
    label(ImVec2(p.x + width - measured.x, p.y), text, color, size);
}
static void section(const char *title) {
    ImGui::Dummy(ImVec2(0, 12 * unit));
    ImVec2 p = ImGui::GetCursorScreenPos();
    label(p, title, white, 26);
    ImGui::Dummy(ImVec2(0, 37 * unit));
}
static void tooltip(bool available) {
    if (!available && ImGui::IsItemHovered(ImGuiHoveredFlags_AllowWhenDisabled))
        ImGui::SetTooltip("This feature is not connected in this build.");
}
static bool toggle(const char *name, bool *value, bool available = true) {
    ImVec2 p = ImGui::GetCursorScreenPos(); float w = ImGui::GetContentRegionAvail().x, h = 54 * unit;
    if (!available) ImGui::PushItemFlag(ImGuiItemFlags_Disabled, true);
    bool clicked = ImGui::InvisibleButton(name, ImVec2(w, h)); remember(name);
    if (!available) ImGui::PopItemFlag();
    if (clicked && available) *value = !*value;
    ImDrawList *d = ImGui::GetWindowDrawList();
    d->AddRectFilled(p, ImVec2(p.x+w, p.y+h), panel, 11*unit);
    d->AddRect(p, ImVec2(p.x+w, p.y+h), *value ? IM_COL32(72,45,102,255) : border, 11*unit, 0, unit);
    label(point(p,20,14), name, available ? white : muted,22);
    ImVec2 a(p.x+w-61*unit,p.y+7*unit), b(p.x+w-17*unit,p.y+47*unit);
    if (*value && available) {
        d->AddRectFilled(point(a,-5,-4), point(b,5,4), IM_COL32(118,54,185,25), 13*unit);
        d->AddRectFilled(a,b,IM_COL32(63,39,88,255),10*unit);
        d->AddRect(a,b,purple,10*unit,0,2*unit);
        d->AddLine(point(a,9,20),point(a,18,28),purple,4*unit);
        d->AddLine(point(a,18,28),point(a,34,12),purple,4*unit);
    } else d->AddRectFilled(a,b,IM_COL32(40,37,46,255),10*unit);
    tooltip(available); return clicked && available;
}
static void slider(const char *name, float *value, float low, float high, const char *format, bool available = true) {
    ImVec2 p = ImGui::GetCursorScreenPos(); float w = ImGui::GetContentRegionAvail().x, h = 52 * unit;
    if (!available) ImGui::PushItemFlag(ImGuiItemFlags_Disabled, true);
    ImGui::InvisibleButton(name,ImVec2(w,h)); remember(name);
    if (!available) ImGui::PopItemFlag();
    if (available && ImGui::IsItemActive()) {
        float t = ImClamp((ImGui::GetIO().MousePos.x-p.x)/w,0.0f,1.0f);
        *value = low+(high-low)*t;
    }
    float t = ImClamp((*value-low)/(high-low),0.0f,1.0f);
    ImDrawList *d = ImGui::GetWindowDrawList();
    d->AddRectFilled(p,ImVec2(p.x+w,p.y+h),panel,10*unit);
    if (available && t > .001f) {
        d->PushClipRect(p,ImVec2(p.x+w*t,p.y+h),true);
        d->AddRectFilled(p,ImVec2(p.x+w,p.y+h),IM_COL32(63,27,105,255),10*unit);
        d->PopClipRect();
        if (t < .99f) d->AddLine(ImVec2(p.x+w*t,p.y+3*unit),ImVec2(p.x+w*t,p.y+h-3*unit),purple,3*unit);
    }
    d->AddRect(p,ImVec2(p.x+w,p.y+h),border,10*unit,0,unit);
    char text[64]; snprintf(text,sizeof(text),format,*value);
    label(point(p,20,13),name,available ? white : muted,22);
    rightLabel(point(p,0,14),w-20*unit,text,available ? white : muted);
    tooltip(available);
}
static void selectRow(const char *name, int *selected, const char *options, bool available = true) {
    ImGui::TextDisabled("%s",name);
    if (!available) ImGui::PushItemFlag(ImGuiItemFlags_Disabled,true);
    ImGui::SetNextItemWidth(-1);
    ImGui::PushStyleVar(ImGuiStyleVar_FramePadding,ImVec2(18*unit,13*unit));
    ImGui::PushStyleColor(ImGuiCol_Button,ImVec4(.065f,.055f,.09f,1));
    ImGui::Combo(name,selected,options); remember(name);
    ImGui::PopStyleColor();
    ImGui::PopStyleVar();
    if (!available) ImGui::PopItemFlag();
}
static void colorRow(const char *name, uint32_t *value) {
    ImGui::TextUnformatted(name); ImGui::SameLine(ImGui::GetWindowWidth()-66*unit);
    float rgba[4] = {(*value&255)/255.0f,((*value>>8)&255)/255.0f,((*value>>16)&255)/255.0f,(*value>>24)/255.0f};
    ImGui::PushID(name);
    if (ImGui::ColorEdit4("##color",rgba,ImGuiColorEditFlags_NoInputs | ImGuiColorEditFlags_NoLabel))
        *value = ImGui::ColorConvertFloat4ToU32(ImVec4(rgba[0],rgba[1],rgba[2],rgba[3]));
    ImGui::PopID();
}

static void icon(ImDrawList *d, ImVec2 c, int which, ImU32 color, float radius) {
    float r = radius, thick = fmaxf(1, r*.16f);
    if (which == 0) {
        d->AddBezierCubic(ImVec2(c.x-r,c.y),ImVec2(c.x-r*.3f,c.y-r),ImVec2(c.x+r*.3f,c.y-r),ImVec2(c.x+r,c.y),color,thick);
        d->AddBezierCubic(ImVec2(c.x-r,c.y),ImVec2(c.x-r*.3f,c.y+r),ImVec2(c.x+r*.3f,c.y+r),ImVec2(c.x+r,c.y),color,thick);
        d->AddCircleFilled(c,r*.32f,color);
    } else if (which == 1) {
        d->AddCircle(c,r,color,24,thick);
        ImVec2 ellipse[24];
        for(int i=0;i<24;++i) { float a=i*6.2831853f/24;
            ellipse[i]=ImVec2(c.x+cosf(a)*r*.45f,c.y+sinf(a)*r); }
        d->AddPolyline(ellipse,24,color,true,thick);
        d->AddLine(ImVec2(c.x-r,c.y),ImVec2(c.x+r,c.y),color,thick);
    } else if (which == 2 || which >= 7) {
        d->AddCircle(c,r*.75f,color,20,thick);
        for (int i=0;i<4;++i) { float a=i*1.5707963f;
            d->AddLine(ImVec2(c.x+cosf(a)*r*.4f,c.y+sinf(a)*r*.4f),ImVec2(c.x+cosf(a)*r*1.15f,c.y+sinf(a)*r*1.15f),color,thick); }
    } else if (which == 3) {
        ImVec2 shape[] = {{c.x,c.y-r},{c.x+r*.75f,c.y+r*.1f},{c.x+r*.6f,c.y+r*.8f},{c.x,c.y+r},{c.x-r*.65f,c.y+r*.6f},{c.x-r*.65f,c.y},{c.x-r*.15f,c.y+r*.1f}};
        d->AddConvexPolyFilled(shape,7,color);
    } else if (which == 4) {
        for (int i=0;i<3;++i) { float y=c.y+(i-1)*r*.65f;
            d->AddLine(ImVec2(c.x-r,y),ImVec2(c.x+r,y),color,thick);
            d->AddCircleFilled(ImVec2(c.x+(i==1?.35f:-.35f)*r,y),r*.24f,color); }
    } else if (which == 5) {
        d->AddRectFilled(ImVec2(c.x-r,c.y-r*.5f),ImVec2(c.x+r,c.y+r*.05f),color,2*unit);
        ImVec2 grip[]={{c.x-r*.25f,c.y},{c.x+r*.25f,c.y},{c.x-r*.05f,c.y+r},{c.x-r*.6f,c.y+r}};
        d->AddConvexPolyFilled(grip,4,color);
    } else {
        d->AddCircleFilled(ImVec2(c.x+r*.3f,c.y-r*.8f),r*.25f,color);
        d->AddLine(ImVec2(c.x+r*.1f,c.y-r*.3f),ImVec2(c.x-r*.3f,c.y+r*.35f),color,thick*2);
        d->AddLine(ImVec2(c.x-r*.3f,c.y+r*.35f),ImVec2(c.x-r*.8f,c.y+r),color,thick*1.5f);
        d->AddLine(ImVec2(c.x-r*.3f,c.y+r*.35f),ImVec2(c.x+r*.35f,c.y+r*.85f),color,thick*1.5f);
        d->AddLine(ImVec2(c.x,c.y-r*.15f),ImVec2(c.x+r*.8f,c.y+r*.1f),color,thick*1.5f);
    }
}

static const char *elementNames[16] = {"Box","Name","Distance","Health bar","Armor bar","Unused","Weapon","Weapon Icon","Money","Armor","Scoped","Flashed","Invul","Ping","Planting","Defusing"};
static void previewPanel(EzwinRuntimeOptions *value, float height) {
    ImGui::BeginChild("esp-preview",ImVec2(0,height),false,ImGuiWindowFlags_NoScrollbar);
    ImGui::TextUnformatted("ESP preview"); ImGui::SameLine(ImGui::GetWindowWidth()-82*unit);
    ImGui::PushStyleColor(ImGuiCol_Button,ImVec4(.30f,.075f,.12f,1));
    if (ImGui::Button("Clear",ImVec2(70*unit,38*unit))) {
        memset(value->esp.placement.enabled,0,sizeof(value->esp.placement.enabled));
        value->esp.box2D = value->esp.box3D = value->esp.lines = false;
    }
    ImGui::PopStyleColor();
    ImVec2 p=ImGui::GetCursorScreenPos(); float w=ImGui::GetContentRegionAvail().x;
    float h=fmaxf(220*unit,ImGui::GetContentRegionAvail().y-8*unit);
    ImGui::InvisibleButton("preview-drop",ImVec2(w,h)); remember("preview-drop");
    ImVec2 a(p.x+w*.24f,p.y+h*.11f),b(p.x+w*.74f,p.y+h*.88f);
    ImDrawList *d=ImGui::GetWindowDrawList();
    d->AddRectFilled(p,ImVec2(p.x+w,p.y+h),IM_COL32(12,11,21,120),8*unit);
    // A neutral training mannequin is used when no portrait asset is available.
    float mid=(a.x+b.x)*.5f, bw=b.x-a.x, bh=b.y-a.y;
    d->AddCircleFilled(ImVec2(mid,a.y+bh*.11f),bw*.16f,IM_COL32(152,151,166,255),30);
    d->AddRectFilled(ImVec2(mid-bw*.13f,a.y+bh*.22f),ImVec2(mid+bw*.13f,a.y+bh*.29f),IM_COL32(110,107,126,255),8*unit);
    ImVec2 torso[]={{mid-bw*.33f,a.y+bh*.26f},{mid+bw*.33f,a.y+bh*.26f},{mid+bw*.28f,a.y+bh*.61f},{mid-bw*.28f,a.y+bh*.61f}};
    d->AddConvexPolyFilled(torso,4,IM_COL32(66,65,82,255));
    d->AddLine(ImVec2(mid-bw*.30f,a.y+bh*.30f),ImVec2(mid-bw*.40f,a.y+bh*.65f),IM_COL32(126,123,145,255),bw*.13f);
    d->AddLine(ImVec2(mid+bw*.30f,a.y+bh*.30f),ImVec2(mid+bw*.40f,a.y+bh*.65f),IM_COL32(126,123,145,255),bw*.13f);
    for (int leg=0;leg<2;++leg) {
        float x=mid+(leg?1:-1)*bw*.15f;
        d->AddLine(ImVec2(x,a.y+bh*.59f),ImVec2(x,a.y+bh*.97f),IM_COL32(79,79,101,255),bw*.21f);
        d->AddRectFilled(ImVec2(x-bw*.13f,b.y-bh*.055f),ImVec2(x+bw*.15f,b.y),IM_COL32(27,26,36,255),3*unit);
    }
    if (value->esp.box2D || value->esp.box3D) d->AddRect(a,b,purple,0,0,1.5f*unit);
    if (value->esp.placement.enabled[3]) {
        d->AddLine(ImVec2(a.x-14*unit,a.y),ImVec2(a.x-14*unit,b.y),IM_COL32(95,91,111,255),2*unit);
        d->AddLine(ImVec2(a.x-14*unit,b.y),ImVec2(a.x-14*unit,a.y+bh*.25f),purple,2*unit);
    }
    if (ImGui::BeginDragDropTarget()) {
        if (const ImGuiPayload *payload=ImGui::AcceptDragDropPayload("EZWIN_ESP_LABEL")) {
            int index=*(const int *)payload->Data;
            if (index>=0 && index<16 && index!=5) {
                ImVec2 mouse=ImGui::GetIO().MousePos;
                int side=mouse.x<a.x?2:(mouse.x>b.x?3:(mouse.y<(a.y+b.y)*.5f?0:1));
                if(mouse.y<a.y && mouse.x<a.x)side=4;
                if(mouse.y<a.y && mouse.x>b.x)side=5;
                if(mouse.y>b.y && mouse.x<a.x)side=6;
                if(mouse.y>b.y && mouse.x>b.x)side=7;
                if(index==3||index==4)side=ImClamp(side,0,3);
                if(index==0)value->esp.box2D=true;
                value->esp.placement.enabled[index]=true; value->esp.placement.position[index]=side;
            }
        }
        ImGui::EndDragDropTarget();
    }
    static const char *samples[16]={"","Leo","[60m]","","","","AK47","AK47","$3200","HK","SCOPED","FLASHED","INVUL","42 MS","PLANTING","DEFUSING"};
    int used[8]={};
    for(int i=1;i<16;++i) {
        if(i==3||i==4||i==5||!value->esp.placement.enabled[i])continue;
        int side=ImClamp(value->esp.placement.position[i],0,7),row=used[side]++;
        float size=16*unit;
        ImVec2 textSize=ImGui::GetFont()->CalcTextSizeA(size,FLT_MAX,0,samples[i]);
        ImVec2 at;
        if(side==0) at=ImVec2(mid-textSize.x*.5f,a.y-(row+1)*23*unit);
        else if(side==1) at=ImVec2(mid-textSize.x*.5f,b.y+(row+1)*20*unit);
        else if(side==2||side==3)at=ImVec2(side==2?a.x-textSize.x-20*unit:b.x+18*unit,a.y+row*23*unit);
        else at=ImVec2(side==4||side==6?a.x-textSize.x-20*unit:b.x+18*unit,
            side<6?a.y-row*23*unit:b.y+row*23*unit);
        ImU32 color=i==14?IM_COL32(232,79,84,255):(i>=8?IM_COL32(73,201,211,255):purple);
        d->AddText(ImGui::GetFont(),size,at,color,samples[i]);
        ImGui::SetCursorScreenPos(at);ImGui::PushID(i);
        ImGui::InvisibleButton("preview-element",textSize);
        if(ImGui::BeginDragDropSource()) {
            ImGui::SetDragDropPayload("EZWIN_ESP_LABEL",&i,sizeof(i));
            ImGui::TextUnformatted(elementNames[i]);ImGui::EndDragDropSource();
        }
        ImGui::PopID();
    }
    ImGui::SetCursorScreenPos(ImVec2(p.x,p.y+h));
    ImGui::EndChild();
}
static void elementTray(EzwinRuntimeOptions *value) {
    section("Drag & Drop elements");
    float available=ImGui::GetContentRegionAvail().x,used=0;
    ImGui::PushStyleColor(ImGuiCol_Button,ImVec4(.08f,.07f,.10f,1));
    for(int i=0;i<16;++i) {
        if(i==5 || value->esp.placement.enabled[i])continue;
        float buttonWidth=ImGui::CalcTextSize(elementNames[i]).x+ImGui::GetStyle().FramePadding.x*2;
        if(used>0 && used+buttonWidth+8*unit<=available) { ImGui::SameLine();used+=8*unit; }
        else used=0;
        ImGui::PushID(i);
        if(ImGui::Button(elementNames[i])) {
            value->esp.placement.enabled[i]=true;
            if(i==0)value->esp.box2D=true;
        }
        char item[64];snprintf(item,sizeof(item),"element:%s",elementNames[i]);remember(item);
        if(ImGui::BeginDragDropSource()) {
            ImGui::SetDragDropPayload("EZWIN_ESP_LABEL",&i,sizeof(i));
            ImGui::TextUnformatted(elementNames[i]); ImGui::EndDragDropSource();
        }
        used+=buttonWidth;
        ImGui::PopID();
    }
    ImGui::PopStyleColor();
}
static void visualControls(EzwinRuntimeOptions *v) {
    elementTray(v); section("Main");
    toggle("Master Switch",&v->esp.enabled);
    toggle("Offscreen Arrows",&v->worldESP.arrows);
    slider("Arrow Size",&v->worldESP.arrowSize,4,24,"%.0f px");
    slider("Arrow Radius",&v->worldESP.arrowRadius,25,400,"%.0f px");
    toggle("Circle Fallback",&v->worldESP.offscreenSoundCircles);
    toggle("Sound ESP",&v->worldESP.sound);
    toggle("Hearable Movement",&v->worldESP.movement);
    toggle("Shooting",&v->worldESP.shots);
    slider("Pulse Scale",&v->worldESP.soundScale,.2f,8,"%.1fx");
    toggle("Skeleton",&v->esp.skeleton); toggle("3D Boxes",&v->esp.box3D);
    toggle("Hitspheres",&v->esp.hitboxes); toggle("Hitsphere Values",&v->esp.hitboxValues);
    toggle("Item ESP",&v->items.enabled); colorRow("Item Color",&v->items.color);
    section("Layout"); selectRow("ESP Style",&v->esp.detailsStyle,"Compact\0Placed labels\0");
    toggle("2D Boxes",&v->esp.box2D); toggle("Snaplines",&v->esp.lines); toggle("Self ESP",&v->esp.selfESP);
    if(ImGui::CollapsingHeader("Labels, placement & colors"))EzwinAdvancedESPMenu(v);
    if(ImGui::CollapsingHeader("Sound & arrow colors"))EzwinAdvancedWorldMenu(&v->worldESP);
}

static void worldLeft(EzwinRuntimeOptions *v) {
    section("Chams"); float w=ImGui::GetContentRegionAvail().x;
    static bool self;
    ImGui::PushStyleColor(ImGuiCol_Button,self ? ImVec4(.07f,.06f,.10f,1) : ImVec4(.25f,.09f,.44f,1));
    if(ImGui::Button("Enemies",ImVec2(w*.5f,48*unit)))self=false;
    ImGui::PopStyleColor();
    ImGui::SameLine(0,0);
    ImGui::PushStyleColor(ImGuiCol_Button,self ? ImVec4(.25f,.09f,.44f,1) : ImVec4(.07f,.06f,.10f,1));
    if(ImGui::Button("Self",ImVec2(w*.5f,48*unit)))self=true;
    ImGui::PopStyleColor();
    bool *enabled = self ? &v->selfChams : &v->playerChams;
    toggle(self ? "Enabled##self-chams" : "Enabled##player-chams",enabled);
    if(*enabled) {
        colorRow("Visible",&v->visibleColor); colorRow("Hidden",&v->hiddenColor);
        toggle("Rainbow",&v->rainbow); toggle("Wireframe",&v->player.wireframe); toggle("Pulsate",&v->player.pulsate);
        selectRow("Style",&v->player.style,"Solid\0Gradient\0Rim\0Smoke\0Hologram\0Marble\0Plasma\0");
        slider("Flow Speed",&v->player.flowSpeed,0,6,"%.2f");
        slider("Outline",&v->player.outlineExponent,.1f,8,"%.2f");
        if(ImGui::CollapsingHeader("More material settings"))EzwinAdvancedChamsMenu(v);
    }
}
static void viewmodelPanel(EzwinRuntimeOptions *v) {
    section("Viewmodel");toggle("Enabled##viewmodel",&v->firstPersonChams);
    slider("Stretch",&v->viewStretch,-1,2,"%.2f");
    section("Weapon FX");
    static int group;selectRow("Model",&group,"Weapon\0Hands\0");
    int mode=(int)v->firstPerson[group].mode;
    selectRow("Pattern",&mode,"Off\0Galaxy\0Smoke\0Hologram\0Voronoi Glow\0Voronoi Cells\0Marble\0Plasma\0Warped Cloud\0");
    v->firstPerson[group].mode=(uint32_t)mode;EzwinChamsOptions *material=&v->firstPerson[group].material;
    toggle("Wrap Model",&material->wrapBase);
    toggle("Custom Color",&material->hasColor);colorRow("Color",&material->color);
    toggle("Custom Rim",&material->hasRimColor);colorRow("Rim",&material->rimColor);
    slider("Speed",&material->speed,0,6,"%.2f");
    slider("Pattern Intensity",&material->patternIntensity,0,5,"%.2f");
    slider("Rim Intensity",&material->rimIntensity,0,5,"%.2f");
}
static void aimLeft(EzwinRuntimeOptions *v) {
    bool available=[EzwinRuntimeStatus()[@"viewHooks"] unsignedIntValue] == 1;
    section("Aimbot"); toggle("Master Switch##aim",&v->aim.selection.enabled,available);
    int bone=(int)v->aim.selection.targetBone;
    selectRow("Target Bone",&bone,"Head\0Neck\0Chest\0Right Arm\0Left Arm\0Left Leg\0Right Leg\0",available);
    v->aim.selection.targetBone=(uint32_t)bone;
    toggle("Firing Check",&v->aim.selection.firingCheck,available);
    toggle("Visibility Check",&v->aim.selection.visibilityCheck,available);
    toggle("Show FOV Circle",&v->aim.showFOV,available);
    slider("FOV",&v->aim.selection.fov,0,180,"%.0f",available);
}
static void aimRight(EzwinRuntimeOptions *v) {
    bool available=[EzwinRuntimeStatus()[@"viewHooks"] unsignedIntValue] == 1;
    section("Aim Assist"); toggle("Fast Assist",&v->aim.fastAssist,available);
    slider("Smoothness",&v->aim.smoothness,0,1,"%.2f",available);
    slider("Max Distance",&v->aim.selection.maxDistance,0,500,"%.0f m",available);
}
static void skinsPanel(EzwinRuntimeOptions *v, float height, bool narrow) {
    section("Weapon Skins"); ImGui::TextDisabled("Skins apply on the next weapon spawn.");
    toggle("Skin Changer",&v->skinChanger);
    static int weapon=-1; static char query[96];
    static NSArray<NSNumber *> *weapons;
    if(!weapons) {
        NSMutableSet<NSNumber *> *ids=[NSMutableSet set];
        for(size_t i=0;i<EzwinSkinCatalogCount;++i)[ids addObject:@(EzwinSkinCatalog[i].weaponDefID)];
        weapons=[[ids allObjects] sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a,NSNumber *b){
            return [EzwinSkinKey(a.intValue) localizedCaseInsensitiveCompare:EzwinSkinKey(b.intValue)]; }];
    }
    float total=ImGui::GetContentRegionAvail().x, left=narrow?total*.40f:total*.36f;
    @synchronized(NSProcessInfo.processInfo) {
        EzwinSkinChanger *changer=EzwinRuntimeSkinChanger();
        ImGui::BeginChild("weapons",ImVec2(left,height),false);
        for(NSNumber *entry in weapons) {
            NSString *key=EzwinSkinKey(entry.intValue); NSRange suffix=[key rangeOfString:@" (" options:NSBackwardsSearch];
            NSString *name=suffix.location==NSNotFound?key:[key substringToIndex:suffix.location];
            bool chosen=changer.selections[key].intValue>0;
            char row[128];snprintf(row,sizeof(row),"%s%s",name.UTF8String,chosen?"  *":"");
            ImGui::PushID(entry.intValue);
            if(ImGui::Selectable(row,weapon==entry.intValue,0,ImVec2(0,28*unit)))weapon=entry.intValue;
            ImGui::PopID();
        }
        ImGui::EndChild();ImGui::SameLine(0,24*unit);
        ImGui::BeginChild("skin-choices",ImVec2(0,height),false);
        if(weapon<0)ImGui::TextDisabled("Pick a weapon on the left.");
        else {
            ImGui::TextUnformatted(EzwinSkinKey(weapon).UTF8String);
            ImGui::SetNextItemWidth(-1);ImGui::InputText("##search-skins",query,sizeof(query));
            if(ImGui::Button("Default skin",ImVec2(-1,36*unit)))[changer setSkinID:0 forKey:EzwinSkinKey(weapon)];
            static NSArray<NSValue *> *rows;
            static int lastWeapon=-2; static char lastQuery[96];
            if(!rows || weapon!=lastWeapon || strcmp(query,lastQuery)) {
                rows=[changer skinsForWeapon:weapon model:0 query:@(query)];
                lastWeapon=weapon; memcpy(lastQuery,query,sizeof(query));
            }
            ImGuiListClipper clipper;clipper.Begin((int)rows.count,35*unit);
            while(clipper.Step())for(int i=clipper.DisplayStart;i<clipper.DisplayEnd;++i) {
                const EzwinSkin *skin=(const EzwinSkin *)rows[i].pointerValue;
                ImGui::PushID(skin->skinID);
                if(ImGui::Selectable(skin->name,changer.selections[EzwinSkinKey(weapon)].intValue==skin->skinID,0,ImVec2(0,29*unit)))
                    [changer toggleSkin:skin];
                ImGui::PopID();
            }
        }
        ImGui::EndChild();
    }
}
static void settingsPanel(EzwinRuntimeOptions *v) {
    section("Settings");
    if(ImGui::Button("Save",ImVec2(100*unit,44*unit))) { EzwinSetRuntimeOptions(v);EzwinSaveMenuSettings(); }
    ImGui::SameLine();if(ImGui::Button("Load",ImVec2(100*unit,44*unit))) { EzwinLoadMenuSettings();EzwinGetRuntimeOptions(v); }
    ImGui::SameLine();if(ImGui::Button("Reset",ImVec2(100*unit,44*unit))) { EzwinResetMenuSettings();EzwinGetRuntimeOptions(v); }
    if(ImGui::Button("Disable all features",ImVec2(-1,48*unit))) { EzwinDisableAllFeatures();EzwinGetRuntimeOptions(v); }
    ImGui::TextWrapped("Settings are saved only when you press Save.");
    ImGui::TextWrapped("Close with X. Tap EZWIN to reopen the menu.");
}
void EzwinDrawMenu(float width,float height) {
    EzwinInitializeMenu(); EzwinRuntimeOptions value;EzwinGetRuntimeOptions(&value);
    value.esp.screenWidth=width;value.esp.screenHeight=height;
    bool aimAvailable=[EzwinRuntimeStatus()[@"viewHooks"] unsignedIntValue]==1;
    if(page==2&&!aimAvailable)page=0;
    if(!EzwinMenuVisible() || width<100 || height<100) { EzwinSetRuntimeOptions(&value);return; }
#ifdef EZWIN_MENU_TESTING
    itemCount=0;
#endif
    ImGuiViewport *viewport=ImGui::GetMainViewport(); ImVec2 area=viewport->WorkSize,origin=viewport->WorkPos;
    bool narrow=area.x<560;
    float mh=fminf(740,area.y*.92f),mw=narrow?area.x-20:fminf(area.x*.90f,mh*1.75f);
    unit=narrow?.66f:mw/1280;
    float sidebar=narrow?64*unit:306*unit,header=108*unit,footer=85*unit;
    ImGui::SetNextWindowPos(ImVec2(origin.x+(area.x-mw)*.5f,origin.y+(area.y-mh)*.5f),ImGuiCond_Always);
    ImGui::SetNextWindowSize(ImVec2(mw,mh),ImGuiCond_Always);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding,ImVec2(0,0));
    ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing,ImVec2(8*unit,8*unit));
    ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding,15*unit);
    bool opened=ImGui::Begin("EzWin Cracked by Cihan",nullptr,ImGuiWindowFlags_NoTitleBar|ImGuiWindowFlags_NoResize|ImGuiWindowFlags_NoMove|ImGuiWindowFlags_NoScrollbar);
    if(opened) {
        ImGui::SetWindowFontScale(20*unit/ImGui::GetFont()->FontSize);
        ImVec2 p=ImGui::GetWindowPos();ImDrawList *d=ImGui::GetWindowDrawList();
        int start=d->VtxBuffer.Size;
        d->AddRectFilled(p,ImVec2(p.x+mw,p.y+mh),white,15*unit);
        ImGui::ShadeVertsLinearColorGradientKeepAlpha(d,start,d->VtxBuffer.Size,p,ImVec2(p.x+mw,p.y+mh),
            IM_COL32(10,10,21,255),IM_COL32(13,8,21,255));
        d->AddRect(p,ImVec2(p.x+mw,p.y+mh),IM_COL32(30,27,39,255),15*unit,0,unit);
        d->AddLine(ImVec2(p.x+12*unit,p.y+header),ImVec2(p.x+mw-12*unit,p.y+header),IM_COL32(29,25,38,255),unit);
        if(!narrow) {
            ImU32 gold=IM_COL32(216,167,55,255);
            d->AddTriangleFilled(point(p,134,29),point(p,143,46),point(p,150,40),gold);
            d->AddTriangleFilled(point(p,144,43),point(p,152,23),point(p,160,43),gold);
            d->AddTriangleFilled(point(p,154,40),point(p,162,46),point(p,170,29),gold);
            d->AddRectFilled(point(p,142,42),point(p,162,48),gold);
            label(point(p,66,55),"EZWIN IOS",white,27);
        }
        const char *title="EzWin Cracked by Cihan";
        float titleSize=narrow?20:23;
        ImVec2 measured=ImGui::GetFont()->CalcTextSizeA(titleSize*unit,FLT_MAX,0,title);
        label(ImVec2(p.x+sidebar+(mw-sidebar-measured.x)*.5f-20*unit,p.y+27*unit),title,white,titleSize);
        if(!narrow) label(ImVec2(p.x+sidebar+(mw-sidebar)*.5f-77*unit,p.y+63*unit),"iOS  /  C-OPS",muted,20);
        ImGui::SetCursorScreenPos(ImVec2(p.x+mw-65*unit,p.y+10*unit));
        if(ImGui::InvisibleButton("Close menu",ImVec2(52*unit,52*unit)))EzwinSetMenuVisible(false);
        remember("Close menu");
        ImVec2 cross=ImGui::GetItemRectMin();
        d->AddLine(point(cross,13,12),point(cross,39,38),IM_COL32(207,56,68,255),4*unit);
        d->AddLine(point(cross,39,12),point(cross,13,38),IM_COL32(207,56,68,255),4*unit);
        ImGui::SetCursorPos(ImVec2(12*unit,header+9*unit));
        ImGui::BeginChild("navigation",ImVec2(sidebar-12*unit,mh-header-footer-9*unit),false);
        for(int i=0;i<pageCount;++i) {
            if(i==2&&!aimAvailable)continue;
            ImVec2 at=ImGui::GetCursorScreenPos(); float w=ImGui::GetContentRegionAvail().x;
            if(ImGui::InvisibleButton(pages[i],ImVec2(w,66*unit)))page=i;remember(pages[i]);
            ImU32 c=page==i?white:muted;
            if(page==i)d=ImGui::GetWindowDrawList(),d->AddRectFilled(point(at,1,10),point(at,5,56),white);
            icon(ImGui::GetWindowDrawList(),point(at,narrow?23:37,33),pageIcons[i],c,16*unit);
            if(!narrow)label(point(at,79,20),pages[i],c,22);
        }
        ImGui::EndChild();
        d=ImGui::GetWindowDrawList();
        d->AddLine(ImVec2(p.x+sidebar,p.y+header),ImVec2(p.x+sidebar,p.y+mh-12*unit),IM_COL32(29,25,38,255),unit);
        ImVec2 foot(p.x+12*unit,p.y+mh-footer);
        d->AddLine(foot,ImVec2(p.x+sidebar,p.y+mh-footer),IM_COL32(29,25,38,255),unit);
        d->AddCircleFilled(point(foot,31,43),24*unit,IM_COL32(43,41,50,255));
        d->AddCircleFilled(point(foot,31,35),8*unit,muted);
        d->AddCircleFilled(point(foot,31,51),12*unit,muted);
        if(!narrow) { label(point(foot,66,24),"Cihan",white,22);label(point(foot,66,47),"1.90.0",muted,17); }
        ImGui::SetCursorPos(ImVec2(sidebar+14*unit,header+8*unit));
        ImGui::BeginChild("content",ImVec2(mw-sidebar-29*unit,mh-header-20*unit),false);
        float contentHeight=ImGui::GetContentRegionAvail().y;
        if(page==3)skinsPanel(&value,contentHeight-138*unit,narrow);
        else if(page==4)settingsPanel(&value);
        else {
            float contentWidth=ImGui::GetContentRegionAvail().x;
            bool columns=!narrow;
            float left=columns?(contentWidth-34*unit)*.49f:contentWidth;
            if(page==0) {
                if(columns) {
                    ImGui::BeginChild("preview-column",ImVec2(left,0),false);
                    previewPanel(&value,contentHeight);ImGui::EndChild();ImGui::SameLine(0,28*unit);
                } else { previewPanel(&value,310*unit); }
                ImGui::BeginChild("visual-controls",ImVec2(0,0),false);visualControls(&value);ImGui::EndChild();
            } else {
                ImGui::BeginChild("left-column",ImVec2(left,columns?0:460*unit),false);
                if(page==1)worldLeft(&value);else if(page==2)aimLeft(&value);
                ImGui::EndChild();if(columns)ImGui::SameLine(0,34*unit);
                ImGui::BeginChild("right-column",ImVec2(0,0),false);
                if(page==1)viewmodelPanel(&value);else if(page==2)aimRight(&value);
                ImGui::EndChild();
            }
        }
        ImGui::EndChild();
        d->AddLine(ImVec2(p.x+mw-34*unit,p.y+mh-16*unit),ImVec2(p.x+mw-16*unit,p.y+mh-16*unit),muted,2*unit);
        d->AddLine(ImVec2(p.x+mw-16*unit,p.y+mh-16*unit),ImVec2(p.x+mw-16*unit,p.y+mh-34*unit),muted,2*unit);
    }
    ImGui::End();ImGui::PopStyleVar(3);EzwinSetRuntimeOptions(&value);
}
