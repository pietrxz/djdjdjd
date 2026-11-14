#include "unity/EzwinOffsets1900.h"
#include "features/aim/EzwinAimMath.h"
#include <string.h>

static bool ValidPointer(uintptr_t pointer) {
    return pointer >= 0x10000ULL && pointer < 0x1000000000000ULL && !(pointer & 7);
}

static uintptr_t ReadPointer(uintptr_t address) {
    uintptr_t value;
    memcpy(&value, (const void *)address, sizeof(value));
    return value;
}

static int ReadCount(uintptr_t array) {
    int count;
    memcpy(&count, (const void *)(array + EzwinField_ArrayLength), sizeof(count));
    return count;
}

int EzwinBoneCount(uintptr_t actor) {
    if (!ValidPointer(actor)) return 0;
    uintptr_t array = ReadPointer(actor + EzwinField_ActorBones);
    if (!ValidPointer(array)) return 0;
    int count = ReadCount(array);
    if (count < 1 || count > 32) return 0;
    return count > 11 ? 11 : count;
}

uintptr_t EzwinBoneObject(uintptr_t actor, uint32_t index) {
    if (index >= 11 || !ValidPointer(actor)) return 0;
    uintptr_t array = ReadPointer(actor + EzwinField_ActorBones);
    if (!ValidPointer(array)) return 0;
    int count = ReadCount(array);
    if (count < 1 || count > 32 || index >= (uint32_t)count) return 0;
    uintptr_t bone = ReadPointer(array + EzwinField_ArrayData + index * sizeof(uintptr_t));
    return ValidPointer(bone) ? bone : 0;
}

int EzwinTargetBoneIndex(uint32_t selection) {
    static const int bones[] = {10, 5, 4, 7, 6, 2, 3};
    return bones[selection < 7 ? selection : 0];
}
