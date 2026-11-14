#include "graphics/shaders/EzwinShaderSource.h"

NSString *EzwinMetalSource(NSString *asset, BOOL vertex) {
    const char *source = nullptr;
    if ([asset isEqualToString:@"ChamsShader"]) source = vertex ? EzwinMetalPlayerVertex() : EzwinMetalPlayerFragment();
    else if ([asset isEqualToString:@"ViewmodelFX"]) source = vertex ? EzwinMetalViewmodelVertex() : EzwinMetalViewmodelFragment();
    else if ([asset isEqualToString:@"ChamsGlow"]) source = vertex ? EzwinMetalGlowVertex() : EzwinMetalGlowFragment();
    else if ([asset isEqualToString:@"SimpleBloom"]) source = vertex ? EzwinMetalBloomVertex() : EzwinMetalBloomFragment();
    else if ([asset isEqualToString:@"SkyCubemap"]) source = vertex ? EzwinMetalSkyVertex() : EzwinMetalSkyFragment();
    if (!source) return nil;
    return [NSString stringWithFormat:@"%s\n%s", EzwinMetalCommon(), source];
}
