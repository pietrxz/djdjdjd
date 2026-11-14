#pragma once
#include "core/EzwinRuntime.h"

EzwinRuntimeOptions EzwinDefaultMenuOptions(void);
void EzwinInitializeMenu(void);
void EzwinApplyMenuStyle(void);
void EzwinDrawMenu(float width, float height);
bool EzwinMenuVisible(void);
void EzwinSetMenuVisible(bool visible);
void EzwinDisableAllFeatures(void);
void EzwinSaveMenuSettings(void);
bool EzwinLoadMenuSettings(void);
void EzwinResetMenuSettings(void);
NSData *EzwinMenuFontData(void);

// The standalone iOS overlay owns its Metal view and its ImGui context.
void EzwinStartOverlay(void);
