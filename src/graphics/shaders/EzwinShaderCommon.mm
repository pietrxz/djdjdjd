#include "graphics/shaders/EzwinShaderSource.h"

const char *EzwinMetalCommon(void) {
    return R"METAL(
#include <metal_stdlib>
#include <metal_texture>
using namespace metal;

float ezHash(float2 cell) {
    float2 seed = fract(cell * float2(123.339996, 456.209991));
    seed += dot(seed, seed + 45.3199997);
    return fract(seed.x * seed.y);
}

float ezNoiseCell(float2 cell, float2 fraction) {
    float2 blend = fraction * fraction * fma(-fraction, float2(2), float2(3));
    float bottomLeft = ezHash(cell);
    float bottomRight = ezHash(cell + float2(1, 0));
    float topLeft = ezHash(cell + float2(0, 1));
    float topRight = ezHash(cell + float2(1, 1));
    float bottom = fma(blend.x, bottomRight - bottomLeft, bottomLeft);
    float top = fma(blend.x, topRight - topLeft, topLeft);
    return fma(blend.y, top - bottom, bottom);
}

float ezNoise(float2 point) { return ezNoiseCell(floor(point), fract(point)); }

float ezFBM(float2 point, float offset = 0) {
    float2 shifted = point + offset;
    float middle = ezNoise(shifted * 2.01999998) * .25;
    float low = fma(ezNoiseCell(floor(shifted), fract(point)), .5, middle);
    return fma(ezNoise(shifted * 4.08039999), .125, low);
}

float ezPower(float value, float exponent) { return exp2(log2(value) * exponent); }
float ezEase(float value) { return (value * value) * fma(value, -2.0, 3.0); }
float ezEaseComplement(float value) { return fma(-fma(value, -2.0, 3.0), value * value, 1.0); }
float3 ezHue(float phase) {
    float3 value = fract(phase + float3(0, .666700006, .333299994));
    return clamp(abs(fma(value, float3(6), float3(-3))) - 1, 0.0f, 1.0f);
}

float3 ezNormalize(float3 vector) { return vector * rsqrt(dot(vector, vector)); }
float4 ezTransform(constant float4 *columns, float4 position) {
    float4 value = fma(columns[0], position.xxxx, columns[1] * position.yyyy);
    value = fma(columns[2], position.zzzz, value);
    return fma(columns[3], position.wwww, value);
}

float3 ezHologram(float facing, float2 uv, float time, float3 tint) {
    float sweep = time * 1.5;
    float3 angular = ezHue(fma(facing, 2.0, time * .300000012));
    float phase = fma(time, .150000006, dot(uv, float2(1.5, .800000012)));
    float3 planar = clamp(abs(fma(fract(phase + float3(.5, 1.16670001, .833299994)),
        float3(6), float3(-3))) - 1, 0.0f, 1.0f) * .5;
    float3 spectrum = fma(angular, float3(.699999988), planar);
    float band = fma(sin(fma(facing, 25.0, sweep)), .5, .099999994);
    band = ezEase(clamp(band * 2.22222209, 0.0f, 1.0f)) * .600000024;
    spectrum *= fma(sin(fma(uv.x, 3.0, sweep)), .150000006, .850000024);
    return fma(spectrum, fma(1 - tint, float3(.5), tint), float3(band));
}

float3 ezMarble(float3 p, float t, float scale, float facing, float3 tint) {
    float a = ezFBM(fma(p.xy, float2(scale), t * float2(.150000006, .105000004)));
    float b = ezFBM(fma(p.yz, float2(scale), t * float2(.135000005, .0944999978)) + 7.13000011);
    float c = ezFBM(fma(p.xz, float2(scale), t * float2(.165000007, .115500003)) + 13.6999998);
    float first = c + (b + a);
    float3 warped = p * 1.70000005;
    a = ezFBM(float2(fma(t, -.120000005, warped.x * scale),
        fma(t, .150000006, warped.y * scale)));
    b = ezFBM(fma(warped.yz, float2(scale), t * float2(-.108000003, .135000005)) + 7.13000011);
    c = ezFBM(fma(warped.xz, float2(scale), t * float2(-.132000014, .165000007)) + 13.6999998);
    float blend = fma(first, .200000018, (c + (b + a)) * .13333334) - .25;
    blend = clamp(blend + blend, 0.0f, 1.0f);
    float square = blend * blend;
    float curve = fma(blend, -2.0, 3.0);
    float marble = square * curve;
    float3 dark = fma(float3(marble), float3(1.27999997, 1.27999997, 1.34000003),
        float3(.0599999987, .0599999987, .0799999982));
    float3 light = fma(float3(fma(curve, square, -.5)),
        float3(.600000024, .600000024, .599999905), float3(.699999988, .699999988, .75));
    float3 color = marble < .5 ? dark : light;
    color = fma(fma(color.yyz, tint, -color.yyz), float3(.25), color);
    float highlight = facing * facing;
    highlight = (highlight * highlight) * facing;
    return fma(float3(highlight), float3(.600000024), color);
}

float3 ezPlasma(float2 uv, float time, float scale, float3 color) {
    float2 p = uv * scale;
    float2 clock = time * float2(1.39999998, 1.10000002);
    float2 phase = fma(p.yx, float2(.560000002, .480000019), clock);
    float2 wave = float2(sin(phase.x), cos(phase.y));
    float first = .0599999987 / max(sqrt(dot(wave, wave)), .0199999996);
    phase = fma(fma(p.yx, float2(.400000006), wave.yx), float2(1.39999998, 1.20000005), clock);
    phase += float2(1.70000005, 2.29999995);
    wave = float2(sin(phase.x), cos(phase.y));
    float second = .0599999987 / max(sqrt(dot(wave, wave)), .0199999996);
    phase = fma(fma(p.yx, float2(.400000006), wave.yx), float2(1.39999998, 1.20000005), clock);
    phase += float2(3.4000001, 4.5999999);
    wave = float2(sin(phase.x), cos(phase.y));
    float third = .0599999987 / max(sqrt(dot(wave, wave)), .0199999996);
    float energy = ezPower(min(third + (second + first), 1.0f), 1.39999998);
    float3 base = float3(0, .0399999991, .119999997);
    base = fma(fma(color, float3(.25), -base), float3(.400000006), base);
    return fma(clamp(color + float3(.400000006, .5, .550000012), 0.0f, 1.0f), float3(energy), base);
}

struct UnityPerCamera_Type {
    float4 _Time, _SinTime, _CosTime, unity_DeltaTime;
    float3 _WorldSpaceCameraPos;
    float4 _ProjectionParams, _ScreenParams, _ZBufferParams, unity_OrthoParams;
};
struct UnityPerDraw_Type {
    float4 objectToWorld[4], worldToObject[4];
    float4 unity_LODFade, unity_WorldTransformParams, unity_RenderingLayer;
};
struct UnityPerFrame_Type {
    float4 ambient, sky, equator, ground, indirectSpecular;
    float4 projection[4], view[4], inverseView[4], viewProjection[4];
    int unity_StereoEyeIndex;
    float4 unity_ShadowColor;
};
)METAL";
}
