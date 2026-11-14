#include "graphics/shaders/EzwinShaderSource.h"

const char *EzwinMetalViewmodelFragment(void) {
    return R"METAL(
constant uint32_t rp_output_remap_mask [[function_constant(1)]];
constant uint rp_output_remap_0 = rp_output_remap_mask & 15;
struct FGlobals_Type {
    float4 _Color, _RimColor;
    float _Pattern, _Speed, _NoiseScale, _PatternIntensity;
    float _RimPower, _RimIntensity, _BaseDarkness, _WrapBase;
};
struct Mtl_FragmentIn {
    float3 objectPosition [[user(TEXCOORD0)]];
    float2 uv [[user(TEXCOORD1)]];
    float3 view [[user(TEXCOORD2)]];
    float3 normal [[user(TEXCOORD3)]];
};
struct Mtl_FragmentOut { half4 SV_Target0 [[color(rp_output_remap_0)]]; };

struct EzwinVoronoi { float first, second, seed; };
EzwinVoronoi ezVoronoi(float2 point) {
    float2 cell = floor(point), fraction = fract(point);
    EzwinVoronoi nearest = {8, 8, 0};
    for (int y = -1; y <= 1; ++y) for (int x = -1; x <= 1; ++x) {
        float2 offset = float2(x, y), neighbor = cell + offset;
        float2 jitter = float2(ezHash(neighbor + 1.70000005), ezHash(neighbor + 3.29999995));
        float2 delta = (offset + jitter) - fraction;
        float distance = dot(delta, delta);
        if (distance < nearest.second) nearest.second = distance;
        if (distance < nearest.first) {
            nearest.second = nearest.first;
            nearest.first = distance;
            nearest.seed = ezHash(neighbor + 5.69999981);
        }
    }
    return nearest;
}

float3 ezVoronoiGlow(float2 uv, float scale, float time, float3 color) {
    EzwinVoronoi cell = ezVoronoi(fma(uv, float2(scale), float2(time * .0299999993)));
    float edge = sqrt(cell.second) - sqrt(cell.first);
    float boundary = ezEaseComplement(clamp(edge * 12.5, 0.0f, 1.0f));
    float glow = ezEaseComplement(clamp(edge * 4, 0.0f, 1.0f));
    float pulse = fma(sin(fma(cell.seed, 30.0, time * 1.5)), .200000003, .800000012);
    float3 hue = ezHue(fma(time, .0299999993, cell.seed)) * .400000006;
    float3 base = fma(color, float3(.300000012), (hue * color) * .699999988);
    float3 light = clamp(color + .5, 0.0f, 1.0f);
    float3 body = base * pulse;
    body = fma(float3(boundary), fma(-base, float3(pulse), light), body);
    return fma(float3(glow) * light, float3(.300000012), body);
}

float3 ezVoronoiCells(float2 uv, float time, float3 color) {
    EzwinVoronoi cell = ezVoronoi(fma(uv, float2(.699999988), float2(time * .0399999991)));
    float edge = ezEase(clamp((sqrt(cell.second) - sqrt(cell.first)) * 25, 0.0f, 1.0f));
    const float3 palette[5] = {float3(.949999988, .100000001, .100000001),
        float3(.0500000007, .850000024, .899999976), float3(1, .800000012, .0500000007),
        float3(.0799999982, .0799999982, .100000001), float3(.850000024, .200000003, .649999976)};
    float3 selected = palette[int(cell.seed * 5)];
    return edge * fma(fma(selected, color + .5, -selected), float3(.25), selected);
}

float3 ezWarpedCloud(float2 uv, float time, float3 color) {
    float2 base = uv * .400000006;
    float2 shifted = fma(uv, float2(.400000006), float2(time * .0799999982));
    float2 first = float2(ezFBM(shifted), ezFBM(shifted + float2(5.19999981, 1.29999995)));
    float2 warped = fma(first, float2(4), base);
    float2 second;
    second.x = ezFBM(fma(float2(time), float2(.119999997), warped + float2(1.70000005, 9.19999981)));
    second.y = ezFBM(fma(float2(time), float2(.119999997), warped) + float2(8.30000019, 2.79999995));
    float density = ezFBM(fma(second, float2(4), base));
    float firstMix = min(sqrt(dot(first, first)) * .600000024, 1.0f);
    float secondMix = min(sqrt(dot(second, second)) * .400000006, 1.0f);
    float3 result = fma(color, float3(.0500000007), min((density * density) * 4, 1.0f) * (color * .949999988));
    result = fma(float3(firstMix), fma(color, float3(.349999994), -result), result);
    result = fma(float3(secondMix), clamp(color + .400000006, 0.0f, 1.0f) - result, result);
    return fma(density, .550000012, .550000012) * result;
}

float ezStars(float2 point, float cellOffset, float time, int layer, float sum) {
    float2 cell = floor(point + cellOffset), fraction = fract(point);
    float threshold = layer == 0 ? .970000029 : (layer == 1 ? .899999976 : .699999988);
    float jitterX = layer == 0 ? 1.70000005 : (layer == 1 ? 2.70000005 : 4.0999999);
    float jitterY = layer == 0 ? 3.29999995 : (layer == 1 ? 5.0999999 : 6.69999981);
    for (int y = -1; y <= 1; ++y) for (int x = -1; x <= 1; ++x) {
        float2 offset = float2(x, y), neighbor = cell + offset;
        float seed = ezHash(neighbor);
        float enabled = seed >= threshold ? 1 : 0;
        float2 jitter = float2(ezHash(neighbor + jitterX), ezHash(neighbor + jitterY)) - .5;
        float2 delta = fma(-jitter, float2(.699999988), (fraction - offset) - .5);
        float radius = max(sqrt(dot(delta, delta)), .00499999989);
        float phase, energy;
        if (layer == 0) {
            float ray = min(abs(delta.x * delta.y) * 100, 1.0f);
            ray = fma(-fma(ray, -2.0, 3.0), ray * ray, 1.0);
            energy = fma(ray, .400000006, .0399999991 / radius) * enabled;
            phase = fma(seed, 30.0, time * 3);
        } else if (layer == 1) {
            energy = (.0199999996 / radius) * enabled;
            phase = fma(seed, 21.0, time * 4) + 1.70000005;
        } else {
            energy = enabled * (.00800000038 / radius);
            phase = fma(seed, 17.0, time * 5) + 3.4000001;
        }
        sum = fma(energy, fma(sin(phase), .400000006, .600000024), sum);
    }
    return sum;
}

float3 ezNebula(float2 uv, float time, float3 color) {
    float a = ezFBM(fma(uv, float2(.600000024), time * float2(.0299999993, .0209999997)));
    float b = ezFBM(fma(uv, float2(1.39999998), time * float2(-.0240000002, .0299999993)) + 5.30000019);
    float c = ezFBM(fma(float2(time), float2(.0179999992, -.0149999997), uv * 2.79999995) + 11.6999998);
    float density = clamp(fma(c, .200000003, fma(a, .550000012, b * .300000012)), 0.0f, 1.0f);
    float3 background;
    if (density < .449999988)
        background = fma(color, float3(.0500000007), (density * 2.22222233) * (color * .550000012));
    else if (density < .75)
        background = fma(color, float3(.600000024), ((density - .449999988) * 3.33333325) * (color * .399999976));
    else background = fma(float3((density - .75) * 4), clamp(color + float3(.349999994, .25, .449999988), 0.0f, 1.0f) - color, color);
    float stars = ezStars(fma(uv, float2(2), time * float2(.0199999996, .0149999997)), 0, time, 0, 0);
    stars = ezStars(fma(uv, float2(4.5), time * float2(.0149999997, .0250000004)), 7, time, 1, stars);
    stars = ezStars(fma(uv, float2(8), time * float2(.00999999978, .0199999996)), 13, time, 2, stars);
    return stars + background;
}

fragment Mtl_FragmentOut xlatMtlMain(constant FGlobals_Type &material [[buffer(0)]],
    constant UnityPerCamera_Type &camera [[buffer(1)]], sampler sampler_BaseTex [[sampler(0)]],
    texture2d<half, access::sample> _BaseTex [[texture(0)]], Mtl_FragmentIn input [[stage_in]]) {
    float time = material._Speed * camera._Time.y;
    float facing = clamp(dot(ezNormalize(input.normal), ezNormalize(input.view)), 0.0f, 1.0f);
    float3 rim = ezPower(1 - facing, material._RimPower) * material._RimColor.rgb;
    float2 uv = input.uv * material._NoiseScale;
    int pattern = int(material._Pattern);
    float3 color;
    float alpha = float(half(material._Color.a));
    switch (pattern) {
        case 1: {
            float a = ezFBM(fma(uv, float2(1.20000005), time * float2(.5, .349999994)));
            float b = ezFBM(fma(uv, float2(2.4000001), time * float2(-.400000006, .5)), 7);
            float c = ezFBM(fma(uv, float2(4.80000019), time * float2(.200000003, -.300000012)), 17);
            float density = ezPower(clamp(fma(c, .200000003, fma(a, .550000012, b * .300000012)), 0.0f, 1.0f), 1.39999998);
            density = min(fma(ezPower(1 - facing, 1.20000005), 1.39999998, .400000006) * density, 1.0f);
            color = fma(float3(density), fma(-material._Color.rgb, float3(.5), float3(1)), material._Color.rgb * .5);
            alpha = density * material._Color.a;
            break;
        }
        case 2: color = ezHologram(facing, input.uv, time, material._Color.rgb + .300000012); break;
        case 3: color = ezVoronoiGlow(input.uv, material._NoiseScale, time, material._Color.rgb); break;
        case 4: color = ezVoronoiCells(uv, time, material._Color.rgb); break;
        case 5: color = ezMarble(input.objectPosition, time, material._NoiseScale, facing, material._Color.rgb + .5); break;
        case 6: color = ezPlasma(input.uv, time, material._NoiseScale, material._Color.rgb); break;
        case 7: color = ezWarpedCloud(uv, time, material._Color.rgb); break;
        default: color = ezNebula(uv, time, material._Color.rgb);
    }
    if (material._WrapBase > .5) {
        half3 sampled = _BaseTex.sample(sampler_BaseTex, input.uv).rgb;
        float blend = clamp(dot(color * material._PatternIntensity, float3(.5)), 0.0f, 1.0f);
        color = fma(float3(blend), fma(color, float3(material._PatternIntensity), -float3(sampled)), float3(sampled));
        alpha = 1;
    } else color = fma(color, float3(material._PatternIntensity), pattern == 1 ? float3(0) : material._Color.rgb * material._BaseDarkness);
    return {half4(float4(fma(rim, float3(material._RimIntensity), color), alpha))};
}
)METAL";
}

const char *EzwinMetalViewmodelVertex(void) {
    return R"METAL(
struct VGlobals_Type { float _ViewStretch; float4 firstPersonVP[4]; };
struct Mtl_VertexIn { float4 position [[attribute(0)]]; float3 normal [[attribute(1)]]; float2 uv [[attribute(2)]]; };
struct Mtl_VertexOut {
    float4 position [[position, invariant]];
    float3 objectPosition [[user(TEXCOORD0)]];
    float2 uv [[user(TEXCOORD1)]];
    float3 view [[user(TEXCOORD2)]];
    float3 normal [[user(TEXCOORD3)]];
};
vertex Mtl_VertexOut xlatMtlMain(constant VGlobals_Type &material [[buffer(0)]],
    constant UnityPerCamera_Type &camera [[buffer(1)]], constant UnityPerDraw_Type &object [[buffer(2)]],
    constant UnityPerFrame_Type &frame [[buffer(3)]], Mtl_VertexIn input [[stage_in]]) {
    float4 viewColumns[4];
    for (int i = 0; i < 4; ++i) viewColumns[i] = ezTransform(frame.view, object.objectToWorld[i]);
    float4 viewPosition = fma(viewColumns[0], input.position.xxxx, viewColumns[1] * input.position.yyyy);
    viewPosition = fma(viewColumns[2], input.position.zzzz, viewPosition);
    viewPosition = fma(viewColumns[3], input.position.wwww, viewPosition);
    viewPosition.z += material._ViewStretch;
    float4 clip = ezTransform(frame.projection, viewPosition);
    float4 world = ezTransform(object.objectToWorld, input.position);
    float magnitude = abs(material.firstPersonVP[0].x) + abs(material.firstPersonVP[1].y);
    magnitude += abs(material.firstPersonVP[2].z);
    magnitude += abs(material.firstPersonVP[3].w);
    if (magnitude > .0000999999975) {
        float4 adjusted = world;
        if (abs(material._ViewStretch) > .0000999999975) {
            float4 view = ezTransform(frame.view, world);
            view.z += material._ViewStretch;
            adjusted = ezTransform(frame.inverseView, view);
        }
        clip = ezTransform(material.firstPersonVP, adjusted);
    }
    float3 normal = float3(dot(input.normal, object.worldToObject[0].xyz),
        dot(input.normal, object.worldToObject[1].xyz), dot(input.normal, object.worldToObject[2].xyz));
    return {clip, input.position.xyz, input.uv, ezNormalize(camera._WorldSpaceCameraPos - world.xyz), ezNormalize(normal)};
}
)METAL";
}
