#include "features/items/EzwinWeaponIcons.h"
#import <MetalKit/MetalKit.h>
#include <string.h>

static id<MTLDevice> iconDevice;
static MTKTextureLoader *loader;
static id<MTLTexture> textures[57];
static bool attempted[57];

int EzwinFindWeaponIcon(const char *weapon) {
    if (!weapon || !*weapon) return -1;
    for (int i = 0; i < 57; ++i)
        if (!strcmp(weapon, EzwinWeaponIconResources[i].name)) return i;
    for (int i = 0; i < 57; ++i) {
        unsigned index = EzwinWeaponIconSearchOrder[i];
        if (strcasestr(weapon, EzwinWeaponIconResources[index].name)) return (int)index;
    }
    return -1;
}

void EzwinSetWeaponIconDevice(id<MTLDevice> device) {
    @synchronized ([MTKTextureLoader class]) {
        if (device == iconDevice) return;
        iconDevice = device;
        loader = device ? [[MTKTextureLoader alloc] initWithDevice:device] : nil;
        for (int i = 0; i < 57; ++i) { textures[i] = nil; attempted[i] = false; }
    }
}

uintptr_t EzwinWeaponIconTexture(const char *weapon, float height, float *width) {
    if (width) *width = 0;
    int index = EzwinFindWeaponIcon(weapon);
    if (index < 0) return 0;
    @synchronized ([MTKTextureLoader class]) {
        if (!iconDevice) EzwinSetWeaponIconDevice(MTLCreateSystemDefaultDevice());
        if (!loader) return 0;
        if (!attempted[index]) {
            attempted[index] = true;
            const EzwinWeaponIconResource *resource = EzwinWeaponIconResources + index;
            NSData *data = [[NSData alloc] initWithBase64EncodedString:@(resource->pngBase64) options:0];
            textures[index] = [loader newTextureWithData:data options:nil error:nil];
        }
        id<MTLTexture> texture = textures[index];
        if (!texture || !texture.height) return 0;
        if (width) *width = height * (float)texture.width / (float)texture.height;
        return (uintptr_t)(__bridge void *)texture;
    }
}
