import Metal
import CoreVideo
import Foundation

class PiPCompositor {

    // 必须与 Metal shader 的 PiPParams 严格对应（24 字节）
    struct PiPParams {
        var pipOriginX: Float
        var pipOriginY: Float
        var pipWidth: Float
        var pipHeight: Float
        var cornerRadius: Float
        var _pad: Float = 0  // Metal float2 对齐补齐到 24 字节

        static func make(backWidth: Int, backHeight: Int,
                         frontWidth: Int, frontHeight: Int,
                         scale: Float = 0.28, margin: Float = 0.03) -> PiPParams {
            // 在归一化坐标中，PiP 宽度固定为 scale，高度根据前摄真实宽高比计算
            // 像素尺寸：pipW_px = scale * backWidth, pipH_px = pipH * backHeight
            // 要使 pipW_px / pipH_px = frontWidth / frontHeight：
            //   pipH = scale * backWidth * frontHeight / (backHeight * frontWidth)
            let frontAspect = Float(frontWidth) / Float(frontHeight)
            let backAspect  = Float(backWidth)  / Float(backHeight)
            let pipW = scale
            let pipH = pipW * backAspect / frontAspect

            return PiPParams(
                pipOriginX: 1.0 - pipW - margin,
                pipOriginY: 1.0 - pipH - margin,
                pipWidth: pipW,
                pipHeight: pipH,
                cornerRadius: 0.015
            )
        }
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private var textureCache: CVMetalTextureCache?
    private var outputPixelBufferPool: CVPixelBufferPool?
    private var outputWidth = 0
    private var outputHeight = 0

    var params = PiPParams(pipOriginX: 0.69, pipOriginY: 0.60,
                           pipWidth: 0.28, pipHeight: 0.37, cornerRadius: 0.015)

    init?() {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let queue = device.makeCommandQueue()
        else { return nil }

        self.device = device
        self.commandQueue = queue

        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)

        do {
            pipelineState = try PiPCompositor.makePipeline(device: device)
        } catch {
            return nil
        }
    }

    // 在 VideoRecorder 拿到前后摄真实尺寸后调用，校正 PiP 宽高比
    func configure(backWidth: Int, backHeight: Int, frontWidth: Int, frontHeight: Int) {
        params = PiPParams.make(backWidth: backWidth, backHeight: backHeight,
                               frontWidth: frontWidth, frontHeight: frontHeight)
    }

    // 用户拖动 PiP 改变角落时同步更新合成视频里的叠层位置
    func updateCorner(isLeft: Bool, isTop: Bool, margin: Float = 0.03) {
        params.pipOriginX = isLeft ? margin : 1.0 - params.pipWidth  - margin
        params.pipOriginY = isTop  ? margin : 1.0 - params.pipHeight - margin
    }

    // 按精确归一化坐标更新叠层位置（自由拖动后使用）
    func updateOrigin(normalizedX: Float, normalizedY: Float) {
        params.pipOriginX = normalizedX
        params.pipOriginY = normalizedY
    }

    // MARK: - 核心合成

    func composite(backBuffer: CVPixelBuffer,
                   frontBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let w = CVPixelBufferGetWidth(backBuffer)
        let h = CVPixelBufferGetHeight(backBuffer)

        ensurePool(width: w, height: h)

        guard
            let outputBuffer = allocateOutputBuffer(),
            let backTex   = texture(from: backBuffer),
            let frontTex  = texture(from: frontBuffer),
            let outputTex = texture(from: outputBuffer)
        else { return nil }

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture     = outputTex
        descriptor.colorAttachments[0].loadAction  = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor  = MTLClearColorMake(0, 0, 0, 1)

        guard
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return nil }

        var metalParams = params
        encoder.setRenderPipelineState(pipelineState)
        // 顶点着色器不再使用 params，仅片元着色器需要
        encoder.setFragmentTexture(backTex,  index: 0)
        encoder.setFragmentTexture(frontTex, index: 1)
        encoder.setFragmentBytes(&metalParams, length: MemoryLayout<PiPParams>.size, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return outputBuffer
    }

    // MARK: - Private

    private func ensurePool(width: Int, height: Int) {
        guard width != outputWidth || height != outputHeight else { return }
        outputWidth  = width
        outputHeight = height

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey  as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &outputPixelBufferPool)
    }

    private func allocateOutputBuffer() -> CVPixelBuffer? {
        guard let pool = outputPixelBufferPool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        return buffer
    }

    private func texture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let cache = textureCache else { return nil }
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, pixelBuffer, nil,
            .bgra8Unorm, w, h, 0, &cvTexture
        )
        guard result == kCVReturnSuccess, let cvTex = cvTexture else { return nil }
        return CVMetalTextureGetTexture(cvTex)
    }

    private static func makePipeline(device: MTLDevice) throws -> MTLRenderPipelineState {
        guard let library = device.makeDefaultLibrary() else {
            throw NSError(domain: "PiPCompositor", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "无法加载 Metal 库"])
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction   = library.makeFunction(name: "pip_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "pip_fragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
}
