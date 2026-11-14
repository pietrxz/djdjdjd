#include "features/audio/EzwinActorSound.h"
#include <string.h>

void EzwinRecordActorSound(EzwinActorSoundState *state, uintptr_t actor, unsigned category, uint64_t now) {
    if (!state || !actor || (category != 5 && category != 6)) return;
    EzwinActorSoundStatus *entry = nullptr, *empty = nullptr;
    for (int i = 0; i < 32; ++i) {
        EzwinActorSoundStatus *current = state->entries + i;
        if (current->actor == actor) { entry = current; break; }
        if (!current->actor && !empty) empty = current;
    }
    if (!entry) {
        entry = empty ? empty : state->entries;
        if (!empty) for (int i = 1; i < 32; ++i) {
            EzwinActorSoundStatus *current = state->entries + i;
            if (current->planting + current->defusing < entry->planting + entry->defusing) entry = current;
        }
        *entry = {actor, 0, 0};
    }
    if (category == 5) entry->planting = now;
    else entry->defusing = now;
}

bool EzwinActorSoundRecent(const EzwinActorSoundState *state, uintptr_t actor, unsigned category,
    float windowMilliseconds, uint64_t now) {
    if (!state || !actor || (category != 5 && category != 6)) return false;
    for (int i = 0; i < 32; ++i) if (state->entries[i].actor == actor) {
        uint64_t timestamp = category == 5 ? state->entries[i].planting : state->entries[i].defusing;
        return timestamp && now - timestamp < (uint64_t)(int64_t)(windowMilliseconds * 1e6f);
    }
    return false;
}

unsigned EzwinClassifySoundName(const uint16_t *name, int length) {
    if (!name || length < 1) return 1;
    char text[96];
    if (length > 95) length = 95;
    for (int i = 0; i < length; ++i) {
        uint16_t c = name[i];
        text[i] = c > 127 ? '?' : (char)(c >= 'A' && c <= 'Z' ? c + 32 : c);
    }
    text[length] = 0;
    static const struct { const char *word; unsigned category; } patterns[] = {
        {"plant",5}, {"defus",6}, {"headshot",8}, {"head_damage",8}, {"deal_damage",7},
        {"armor_break",7}, {"flesh",7}, {"body_hit",7}, {"kevlar",7}, {"melee_",7},
        {"hit",3}, {"bullet_impact",3}, {"shoot",2}, {"_fire",2}, {"dryfire",2}, {"shell_drop",2}
    };
    for (unsigned i = 0; i < sizeof(patterns) / sizeof(*patterns); ++i)
        if (strstr(text, patterns[i].word)) return patterns[i].category;
    return 1;
}
