#include "unity/EzwinOffsets1900.h"
#include "features/audio/EzwinSoundEvents.h"
#include <limits.h>
#include <stddef.h>
#include <pthread.h>

static_assert(sizeof(EzwinSoundEvent) == EzwinField_SoundEventSize, "Sound event layout mismatch");
static_assert(offsetof(EzwinSoundEvent, category) == EzwinField_SoundCategory, "Sound category offset mismatch");
static_assert(offsetof(EzwinSoundEvent, active) == EzwinField_SoundActive, "Sound active flag offset mismatch");
static pthread_mutex_t gSoundEventsMutex = PTHREAD_MUTEX_INITIALIZER;

void EzwinRecordSoundEvent(EzwinSoundEvent events[16], uintptr_t actor, uint8_t category,
    EzwinPosition position, uint32_t frame, double now, float strength) {
    pthread_mutex_lock(&gSoundEventsMutex);
    int firstFree = -1;
    int oldest = 0;
    int32_t oldestFrame = INT_MAX;

    for (int i = 0; i < 16; i++) {
        EzwinSoundEvent *event = &events[i];
        if (event->active == 1) {
            if (event->actor == actor) {
                if ((int32_t)(frame - event->lastFrame) > 30) {
                    event->startedAt = now;
                    event->strength = strength;
                    event->reserved = 0;
                }
                event->position = position;
                event->lastFrame = frame;
                pthread_mutex_unlock(&gSoundEventsMutex);
                return;
            }
            if ((int32_t)event->lastFrame < oldestFrame) {
                oldest = i;
                oldestFrame = (int32_t)event->lastFrame;
            }
        } else if (firstFree < 0) {
            firstFree = i;
        }
    }

    EzwinSoundEvent *event = &events[firstFree >= 0 ? firstFree : oldest];
    event->actor = actor;
    event->startedAt = now;
    event->position = position;
    event->lastFrame = frame;
    event->category = category;
    event->strength = strength;
    event->active = 1;
    event->reserved = 0;
    pthread_mutex_unlock(&gSoundEventsMutex);
}
