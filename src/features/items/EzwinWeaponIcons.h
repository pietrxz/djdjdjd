#pragma once
#import <Metal/Metal.h>
#import <Foundation/Foundation.h>

typedef struct {
    const char *name, *pngBase64;
    unsigned width, height;
} EzwinWeaponIconResource;
extern const EzwinWeaponIconResource EzwinWeaponIconResources[57];
extern const unsigned EzwinWeaponIconSearchOrder[57];

extern "C" int EzwinFindWeaponIcon(const char *weapon);
void EzwinSetWeaponIconDevice(id<MTLDevice> device);
uintptr_t EzwinWeaponIconTexture(const char *weapon, float height, float *width);
