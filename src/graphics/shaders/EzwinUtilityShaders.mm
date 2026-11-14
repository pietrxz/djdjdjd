#include "graphics/shaders/EzwinShaderSource.h"

const char *EzwinMetalGlowVertex(void) {
    return R"METAL(
struct Mtl_VertexIn { float4 position [[attribute(0)]]; };
struct Mtl_VertexOut { float4 position [[position, invariant]]; };
vertex Mtl_VertexOut xlatMtlMain(constant UnityPerDraw_Type &object [[buffer(0)]],
    constant UnityPerFrame_Type &frame [[buffer(1)]], Mtl_VertexIn input [[stage_in]]) {
    float4 world = fma(object.objectToWorld[0], input.position.xxxx, object.objectToWorld[1] * input.position.yyyy);
    world = fma(object.objectToWorld[2], input.position.zzzz, world) + object.objectToWorld[3];
    return {ezTransform(frame.viewProjection, world)};
}
)METAL";
}

const char *EzwinMetalGlowFragment(void) {
    return R"METAL(
constant uint32_t rp_output_remap_mask [[function_constant(1)]];
constant uint rp_output_remap_0 = rp_output_remap_mask & 15;
struct FGlobals_Type { float4 color; float _Intensity; };
struct Mtl_FragmentOut { half4 SV_Target0 [[color(rp_output_remap_0)]]; };
fragment Mtl_FragmentOut xlatMtlMain(constant FGlobals_Type &material [[buffer(0)]]) {
    return {half4(float4(material.color.rgb * material._Intensity, material.color.a))};
}
)METAL";
}

const char *EzwinMetalBloomVertex(void) {
    return R"METAL(
struct Mtl_VertexIn { float4 position [[attribute(0)]]; float2 uv [[attribute(1)]]; };
struct Mtl_VertexOut { float4 position [[position, invariant]]; half2 uv [[user(TEXCOORD0)]]; };
vertex Mtl_VertexOut xlatMtlMain(constant UnityPerDraw_Type &object [[buffer(0)]],
    constant UnityPerFrame_Type &frame [[buffer(1)]], Mtl_VertexIn input [[stage_in]]) {
    float4 world = fma(object.objectToWorld[0], input.position.xxxx, object.objectToWorld[1] * input.position.yyyy);
    world = fma(object.objectToWorld[2], input.position.zzzz, world) + object.objectToWorld[3];
    return {ezTransform(frame.viewProjection, world), half2(input.uv)};
}
)METAL";
}

const char *EzwinMetalBloomFragment(void) {
    return R"METAL(
constant uint32_t rp_output_remap_mask [[function_constant(1)]];
constant uint rp_output_remap_0 = rp_output_remap_mask & 15;
struct FGlobals_Type { float4 _MainTex_TexelSize; float _Threshold, _Intensity, _BloomStage; };
struct Mtl_FragmentIn { half2 uv [[user(TEXCOORD0)]]; };
struct Mtl_FragmentOut { float4 SV_Target0 [[color(rp_output_remap_0)]]; };
fragment Mtl_FragmentOut xlatMtlMain(constant FGlobals_Type &material [[buffer(0)]],
    sampler sampler_MainTex [[sampler(0)]], sampler sampler_BloomTex [[sampler(1)]],
    texture2d<half, access::sample> _MainTex [[texture(0)]],
    texture2d<half, access::sample> _BloomTex [[texture(1)]], Mtl_FragmentIn input [[stage_in]]) {
    float2 uv = float2(input.uv);
    float4 center = float4(_MainTex.sample(sampler_MainTex, uv));
    int stage = int(material._BloomStage + .5);
    if (stage == 1 || stage == 2) {
        float2 step = stage == 1 ? float2(material._MainTex_TexelSize.x, 0) : float2(0, material._MainTex_TexelSize.y);
        float2 nearPositive = fma(step, float2(1.38461542), uv);
        float2 nearNegative = fma(-step, float2(1.38461542), uv);
        float2 farPositive = fma(step, float2(3.23076916), uv);
        float2 farNegative = fma(-step, float2(3.23076916), uv);
        float4 result = float4(_MainTex.sample(sampler_MainTex, nearPositive)) * .31621623;
        result = fma(center, float4(.227027029), result);
        result = fma(float4(_MainTex.sample(sampler_MainTex, nearNegative)), float4(.31621623), result);
        result = fma(float4(_MainTex.sample(sampler_MainTex, farPositive)), float4(.0702702701), result);
        return {fma(float4(_MainTex.sample(sampler_MainTex, farNegative)), float4(.0702702701), result)};
    }
    if (stage == 3) return {fma(float4(_BloomTex.sample(sampler_BloomTex, uv)), float4(material._Intensity), center)};
    float brightness = max(center.r, max(center.b, center.g));
    float threshold = max(brightness - material._Threshold, 0.0f) / max(brightness, .0000999999975);
    return {center * threshold};
}
)METAL";
}

const char *EzwinMetalSkyVertex(void) {
    return R"METAL(
struct VGlobals_Type { float _Rotation; };
struct Mtl_VertexIn { float4 position [[attribute(0)]]; };
struct Mtl_VertexOut { float4 position [[position, invariant]]; float3 direction [[user(TEXCOORD0)]]; };
vertex Mtl_VertexOut xlatMtlMain(constant VGlobals_Type &material [[buffer(0)]],
    constant UnityPerDraw_Type &object [[buffer(1)]], constant UnityPerFrame_Type &frame [[buffer(2)]],
    Mtl_VertexIn input [[stage_in]]) {
    float4 world = fma(object.objectToWorld[0], input.position.xxxx, object.objectToWorld[1] * input.position.yyyy);
    world = fma(object.objectToWorld[2], input.position.zzzz, world) + object.objectToWorld[3];
    float4 clip = ezTransform(frame.viewProjection, world);
    clip.z = .00999999978;
    float angle = material._Rotation * .0174532924;
    float sine = sin(angle), cosine = cos(angle);
    float3 direction = float3(fma(cosine, input.position.x, -(sine * input.position.z)), input.position.y,
        fma(cosine, input.position.z, sine * input.position.x));
    return {clip, direction};
}
)METAL";
}

const char *EzwinMetalSkyFragment(void) {
    return R"METAL(
constant uint32_t rp_output_remap_mask [[function_constant(1)]];
constant uint rp_output_remap_0 = rp_output_remap_mask & 15;
struct FGlobals_Type { float4 _Color; };
struct Mtl_FragmentIn { float3 direction [[user(TEXCOORD0)]]; };
struct Mtl_FragmentOut { half4 SV_Target0 [[color(rp_output_remap_0)]]; };
fragment Mtl_FragmentOut xlatMtlMain(constant FGlobals_Type &material [[buffer(0)]],
    sampler sampler_Tex [[sampler(0)]], texturecube<half, access::sample> _Tex [[texture(0)]],
    Mtl_FragmentIn input [[stage_in]]) {
    return {half4(float4(_Tex.sample(sampler_Tex, ezNormalize(input.direction))) * material._Color)};
}
)METAL";
}
