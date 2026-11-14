#include "features/audio/EzwinAudioHooks.h"
#include "features/audio/EzwinActorSound.h"

static EzwinAudioPositionOriginal originalPosition;
static EzwinAudioClipOriginal originalClip;
static EzwinAudioPlayOriginal originalPlay;
static EzwinAudioName clipName;
static EzwinAudioObserver onSound;
static thread_local struct { EzwinPosition position; uintptr_t clip; bool positioned; } pending;

void EzwinConfigureAudioHooks(EzwinAudioPositionOriginal position, EzwinAudioClipOriginal clip,
    EzwinAudioPlayOriginal play, EzwinAudioName name, EzwinAudioObserver observer) {
    originalPosition = position; originalClip = clip; originalPlay = play; clipName = name; onSound = observer;
}
void EzwinAudioPositionHook(uintptr_t object, const EzwinPosition *position) {
    if (position) { pending.position = *position; pending.positioned = true; }
    if (originalPosition) originalPosition(object, position);
}
void EzwinAudioClipHook(uintptr_t object, uintptr_t clip) {
    pending.clip = clip;
    if (originalClip) originalClip(object, clip);
}
void EzwinAudioPlayHook(uintptr_t object, uint64_t delay) {
    if (object && pending.positioned && pending.clip && clipName) {
        uintptr_t view[2] = {};
        clipName(pending.clip, view);
        unsigned category = EzwinClassifySoundName((const uint16_t *)view[0], (int)view[1]);
        if (category == 2 || category == 5 || category == 6) {
            // Consume thread-local position only after a recognized world-space sound.
            EzwinPosition position = pending.position;
            pending.positioned = false;
            if (onSound) onSound(category, position);
        }
    }
    if (originalPlay) originalPlay(object, delay);
}
