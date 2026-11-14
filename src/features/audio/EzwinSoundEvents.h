#pragma once
#include <stdint.h>

typedef struct { float x, y, z; } EzwinPosition;

typedef struct {
    uintptr_t actor;
    double startedAt;
    EzwinPosition position;
    uint32_t lastFrame;
    float strength;
    uint8_t category;
    uint8_t active;
    uint8_t padding[2];
    uint64_t reserved;
} EzwinSoundEvent;

#ifdef __cplusplus
extern "C" {
#endif
void EzwinRecordSoundEvent(EzwinSoundEvent events[16], uintptr_t actor, uint8_t category,
    EzwinPosition position, uint32_t frame, double now, float strength);
#ifdef __cplusplus
}
#endif
