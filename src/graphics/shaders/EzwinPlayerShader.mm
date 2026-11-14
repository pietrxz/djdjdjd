#include "graphics/shaders/EzwinShaderSource.h"

const char *EzwinMetalPlayerFragment(void) {
    return R"METAL(
constant uint32_t rp_output_remap_mask [[function_constant(1)]];
constant uint rp_output_remap_0 = rp_output_remap_mask & 15;
struct FGlobals_Type {
    float4 _Color, _ColorSec;
    float _Style, _Wireframe, _WireThickness, _PulsateRate, _FlowSpeed;
    float _OutlineExp, _OutlineInner, _NoiseScale, _SmokeDrift, _SmokeDensity, _SmokeRimBoost;
};
struct Mtl_FragmentIn {
    float rim [[user(TEXCOORD0)]];
    float3 worldPosition [[user(TEXCOORD1)]];
    float2 uv [[user(TEXCOORD2)]];
    float3 normal [[user(TEXCOORD3)]];
    float3 objectPosition [[user(TEXCOORD4)]];
};
struct Mtl_FragmentOut { half4 SV_Target0 [[color(rp_output_remap_0)]]; };

float4 ezSmoke(constant FGlobals_Type &material, Mtl_FragmentIn input, float time) {
    float drift = material._SmokeDrift * time;
    float2 uv = input.uv * material._NoiseScale;
    float first = ezFBM(fma(uv, float2(1.20000005), float2(drift, drift * .699999988)));
    float second = ezFBM(fma(uv, float2(2.4000001), float2(drift * -.800000012, drift)), 7);
    float third = ezFBM(fma(uv, float2(4.80000019), drift * float2(.400000006, -.600000024)), 17);
    float density = fma(third, .200000003, fma(first, .550000012, second * .300000012));
    density = ezPower(clamp(density, 0.0f, 1.0f), 1.39999998);
    float rim = ezPower(clamp(input.rim, 0.0f, 1.0f), 1.20000005);
    density = clamp(density * fma(rim, material._SmokeRimBoost, .400000006), 0.0f, 1.0f);
    return float4(material._Color.rgb, (density * material._SmokeDensity) * material._Color.a);
}

fragment Mtl_FragmentOut xlatMtlMain(constant FGlobals_Type &material [[buffer(0)]],
    constant UnityPerCamera_Type &camera [[buffer(1)]], Mtl_FragmentIn input [[stage_in]]) {
    float4 color = material._Color;
    float time = camera._Time.y;
    int style = int(material._Style + .5);
    switch (style) {
        case 1: {
            float blend = fma(sin(fma(input.worldPosition.y, .5, material._FlowSpeed * time)), .5, .5);
            color = fma(float4(blend), material._ColorSec - material._Color, material._Color);
            break;
        }
        case 2: {
            float rim = ezPower(clamp(input.rim, 0.0f, 1.0f), material._OutlineExp);
            color.rgb = fma(material._Color.rgb, float3(.25), (material._Color.rgb * 1.35000002) * rim);
            color.a = fma(rim, 1 - material._OutlineInner, material._OutlineInner) * material._Color.a;
            break;
        }
        case 3: color = ezSmoke(material, input, time); break;
        case 4: {
            float facing = clamp(dot(ezNormalize(input.normal), ezNormalize(camera._WorldSpaceCameraPos - input.worldPosition)), 0.0f, 1.0f);
            color.rgb = ezHologram(facing, input.uv, material._FlowSpeed * time,
                float3(half3(material._Color.rgb) + half3(.300000012)));
            break;
        }
        case 5: {
            float facing = clamp(dot(ezNormalize(input.normal), ezNormalize(camera._WorldSpaceCameraPos - input.worldPosition)), 0.0f, 1.0f);
            color.rgb = ezMarble(input.objectPosition, material._FlowSpeed * time, material._NoiseScale,
                facing, float3(half3(material._Color.rgb) + half3(.5)));
            break;
        }
        case 6: color.rgb = ezPlasma(input.uv, material._FlowSpeed * time, material._NoiseScale, material._Color.rgb); break;
        default:
            if (material._Wireframe > .5) {
                if (input.rim < material._WireThickness) discard_fragment();
                color.a *= clamp((input.rim - material._WireThickness) / (1 - material._WireThickness), 0.0f, 1.0f);
            }
    }
    half4 result = half4(color);
    if (material._PulsateRate > 0) {
        float pulse = fma(sin((material._PulsateRate * time) * 6.28318024), .25, .75);
        result.a = half(pulse * float(result.a));
    }
    return {result};
}
)METAL";
}

const char *EzwinMetalPlayerVertex(void) {
    return R"METAL(
struct VGlobals_Type { float _Style; float _GlowScale; };
struct Mtl_VertexIn {
    float4 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 uv [[attribute(2)]];
};
struct Mtl_VertexOut {
    float4 position [[position, invariant]];
    float rim [[user(TEXCOORD0)]];
    float3 worldPosition [[user(TEXCOORD1)]];
    float2 uv [[user(TEXCOORD2)]];
    float3 normal [[user(TEXCOORD3)]];
    float3 objectPosition [[user(TEXCOORD4)]];
};
vertex Mtl_VertexOut xlatMtlMain(constant VGlobals_Type &material [[buffer(0)]],
    constant UnityPerCamera_Type &camera [[buffer(1)]], constant UnityPerDraw_Type &object [[buffer(2)]],
    constant UnityPerFrame_Type &frame [[buffer(3)]], Mtl_VertexIn input [[stage_in]]) {
    float3 normal = fma(object.objectToWorld[0].xyz, input.normal.xxx, object.objectToWorld[1].xyz * input.normal.yyy);
    normal = ezNormalize(fma(object.objectToWorld[2].xyz, input.normal.zzz, normal));
    float4 world = ezTransform(object.objectToWorld, input.position);
    float3 direction = ezNormalize(camera._WorldSpaceCameraPos - world.xyz);
    float rim = max(1 - abs(dot(normal, direction)), 0.0f);
    float extrusion = (rim * rim) * material._GlowScale;
    float3 position = int(material._Style + .5) ? world.xyz : fma(normal, float3(extrusion), world.xyz);
    float4 clip = ezTransform(frame.viewProjection, float4(position, world.w));
    return {clip, rim, position, input.uv, normal, input.position.xyz};
}
)METAL";
}
