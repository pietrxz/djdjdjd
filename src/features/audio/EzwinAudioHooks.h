#pragma once
#include "features/audio/EzwinSoundEvents.h"
typedef void (*EzwinAudioPositionOriginal)(uintptr_t object, const EzwinPosition *position);
typedef void (*EzwinAudioClipOriginal)(uintptr_t object, uintptr_t clip);
typedef void (*EzwinAudioPlayOriginal)(uintptr_t object, uint64_t delay);
typedef void (*EzwinAudioName)(uintptr_t clip, uintptr_t *utf16View);
typedef void (*EzwinAudioObserver)(unsigned category, EzwinPosition position);
void EzwinConfigureAudioHooks(EzwinAudioPositionOriginal position, EzwinAudioClipOriginal clip,
    EzwinAudioPlayOriginal play, EzwinAudioName name, EzwinAudioObserver observer);
void EzwinAudioPositionHook(uintptr_t object, const EzwinPosition *position);
void EzwinAudioClipHook(uintptr_t object, uintptr_t clip);
void EzwinAudioPlayHook(uintptr_t object, uint64_t delay);
