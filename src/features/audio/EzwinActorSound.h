#pragma once
#include "features/audio/EzwinSoundEvents.h"

typedef struct { uintptr_t actor; uint64_t planting, defusing; } EzwinActorSoundStatus;
typedef struct { EzwinActorSoundStatus entries[32]; } EzwinActorSoundState;
// The runtime holds its shared actor lock while updating or reading this state.
extern "C" {
void EzwinRecordActorSound(EzwinActorSoundState *state, uintptr_t actor, unsigned category, uint64_t now);
bool EzwinActorSoundRecent(const EzwinActorSoundState *state, uintptr_t actor, unsigned category,
    float windowMilliseconds, uint64_t now);
unsigned EzwinClassifySoundName(const uint16_t *name, int length);
}
