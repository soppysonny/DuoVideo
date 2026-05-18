#include <metal_stdlib>
using namespace metal;

#define MAX_PIP_LAYERS 4

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// 单个 PiP 层参数，与 Swift 端 LayerParams 严格对应（40 字节）
struct LayerParams {
    float2 origin;        // 归一化左上角 (0..1)
    float2 size;          // 归一化宽高 (0..1)
    float2 cropOrigin;    // 前摄裁剪区域起点 UV (0..1)
    float2 cropSize;      // 前摄裁剪区域大小 UV (0..1)
    float  cornerRadius;  // 归一化角半径
    float  mirrorFront;   // 1.0 = 镜像, 0.0 = 不镜像
};

// 所有层参数，与 Swift 端 CompositorParams 严格对应（176 字节）
struct CompositorParams {
    LayerParams layers[MAX_PIP_LAYERS];
    int   activeCount;
    float aspectRatio; // 输出帧宽高比 (width/height)，用于像素等比 SDF 计算
    float _pad1;
    float _pad2;
};

// 在像素等比坐标中计算圆角矩形 SDF，避免圆形在非方形视频中变为椭圆
static float sdRoundedRect(float2 p, float2 origin, float2 size, float r, float ar) {
    // 将 UV 坐标缩放到像素等比空间（X × ar，使 1 单位 = 1 像素高度）
    float2 pS     = float2(p.x * ar,      p.y);
    float2 oS     = float2(origin.x * ar, origin.y);
    float2 sS     = float2(size.x * ar,   size.y);
    float  rS     = r * ar;
    float2 center = oS + sS * 0.5;
    float2 q      = abs(pS - center) - sS * 0.5 + rS;
    float  dist   = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rS;
    return dist / ar; // 还原到 UV 空间供阈值比较
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
        float sdf = sdRoundedRect(uv, layer.origin, layer.size, layer.cornerRadius, params.aspectRatio);

        if (sdf > 0.004) { continue; }

        float2 pipUV = (uv - layer.origin) / layer.size;
        // 应用裁剪区域
        pipUV = layer.cropOrigin + pipUV * layer.cropSize;
        // 应用镜像
        if (layer.mirrorFront > 0.5) { pipUV.x = 1.0 - pipUV.x; }

        if (pipUV.x < 0.0 || pipUV.x > 1.0 || pipUV.y < 0.0 || pipUV.y > 1.0) { continue; }

        float4 pipColor = samplePiP(i, pipUV, pip0, pip1, pip2, pip3, s);
        float alpha = 1.0 - smoothstep(-0.002, 0.0, sdf);
        color = mix(color, pipColor, alpha);
    }

    return color;
}
