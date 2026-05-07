#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// 必须与 Swift 端 PiPParams 严格对应（24 字节）
struct PiPParams {
    float2 pipOrigin;    // top-left of PiP, normalized (0..1)
    float2 pipSize;      // width/height of PiP, normalized (0..1)
    float  cornerRadius;
    float  _pad;         // 补齐到 24 字节
};

static float sdRoundedRect(float2 p, float2 origin, float2 size, float r) {
    float2 center = origin + size * 0.5;
    float2 q = abs(p - center) - size * 0.5 + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// 顶点着色器只负责输出覆盖全屏的四边形，不涉及 PiP 参数
vertex VertexOut pip_vertex(uint vertexID [[vertex_id]]) {
    float2 positions[4] = {
        {-1.0,  1.0},
        { 1.0,  1.0},
        {-1.0, -1.0},
        { 1.0, -1.0}
    };
    float2 uvs[4] = {
        {0.0, 0.0},
        {1.0, 0.0},
        {0.0, 1.0},
        {1.0, 1.0}
    };
    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = uvs[vertexID];
    return out;
}

// PiP 判断必须在片元着色器里做（顶点插值无法正确传递区域内外信息）
fragment float4 pip_fragment(VertexOut in [[stage_in]],
                             texture2d<float> backTexture  [[texture(0)]],
                             texture2d<float> frontTexture [[texture(1)]],
                             constant PiPParams &params    [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    float2 uv = in.texCoord;
    float4 backColor = backTexture.sample(s, uv);

    float sdf = sdRoundedRect(uv, params.pipOrigin, params.pipSize, params.cornerRadius);

    // 明显在 PiP 区域外，直接返回后摄
    if (sdf > 0.004) {
        return backColor;
    }

    // 将屏幕 UV 映射到前摄纹理坐标
    float2 frontUV = (uv - params.pipOrigin) / params.pipSize;

    if (frontUV.x < 0.0 || frontUV.x > 1.0 || frontUV.y < 0.0 || frontUV.y > 1.0) {
        return backColor;
    }

    float4 frontColor = frontTexture.sample(s, frontUV);

    // SDF 软边抗锯齿
    float alpha = 1.0 - smoothstep(-0.002, 0.0, sdf);
    return mix(backColor, frontColor, alpha);
}
