#include <metal_stdlib>
using namespace metal;

#define MAX_PIP_LAYERS 4

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// 单个 PiP 层参数，与 Swift 端 LayerParams 严格对应（24 字节）
struct LayerParams {
    float2 origin;        // 归一化左上角 (0..1)
    float2 size;          // 归一化宽高 (0..1)
    float  cornerRadius;  // 归一化角半径
    float  _pad;          // 对齐补齐到 24 字节
};

// 所有层参数，与 Swift 端 CompositorParams 严格对应（112 字节）
struct CompositorParams {
    LayerParams layers[MAX_PIP_LAYERS];
    int   activeCount;
    float _pad0;
    float _pad1;
    float _pad2;
};

static float sdRoundedRect(float2 p, float2 origin, float2 size, float r) {
    float2 center = origin + size * 0.5;
    float2 q = abs(p - center) - size * 0.5 + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

static float4 samplePiP(int idx, float2 uv,
                         texture2d<float> p0, texture2d<float> p1,
                         texture2d<float> p2, texture2d<float> p3,
                         sampler s) {
    if (idx == 0) return p0.sample(s, uv);
    if (idx == 1) return p1.sample(s, uv);
    if (idx == 2) return p2.sample(s, uv);
    return p3.sample(s, uv);
}

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

fragment float4 pip_fragment(VertexOut in                      [[stage_in]],
                             texture2d<float> backTexture      [[texture(0)]],
                             texture2d<float> pip0             [[texture(1)]],
                             texture2d<float> pip1             [[texture(2)]],
                             texture2d<float> pip2             [[texture(3)]],
                             texture2d<float> pip3             [[texture(4)]],
                             constant CompositorParams& params [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    float2 uv = in.texCoord;
    float4 color = backTexture.sample(s, uv);

    for (int i = 0; i < params.activeCount; i++) {
        LayerParams layer = params.layers[i];
        float sdf = sdRoundedRect(uv, layer.origin, layer.size, layer.cornerRadius);

        if (sdf > 0.004) { continue; }

        float2 pipUV = (uv - layer.origin) / layer.size;
        if (pipUV.x < 0.0 || pipUV.x > 1.0 || pipUV.y < 0.0 || pipUV.y > 1.0) { continue; }

        float4 pipColor = samplePiP(i, pipUV, pip0, pip1, pip2, pip3, s);
        float alpha = 1.0 - smoothstep(-0.002, 0.0, sdf);
        color = mix(color, pipColor, alpha);
    }

    return color;
}
