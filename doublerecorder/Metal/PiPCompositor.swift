import Metal
import CoreVideo
import Foundation

class PiPCompositor {

    // 单个 PiP 层参数，与 Metal 端 LayerParams 严格对应（24 字节）
    struct LayerParams {
        var originX: Float
        var originY: Float
        var sizeW: Float
        var sizeH: Float
        var cornerRadius: Float
        var _pad: Float = 0
    }

    // 所有层参数，与 Metal 端 CompositorParams 严格对应（112 字节）
    struct CompositorParams {
        var layer0: LayerParams
        var layer1: LayerParams
        var layer2: LayerParams
        var layer3: LayerParams
        var activeCount: Int32
        var _pad0: Float = 0
        var _pad1: Float = 0
        var _pad2: Float = 0
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private var textureCache: CVMetalTextureCache?
    private var outputPixelBufferPool: CVPixelBufferPool?
    private var outputWidth = 0
    private var outputHeight = 0

    private var compositorParams = CompositorParams(
        layer0: LayerParams(originX: 0.69, originY: 0.60, sizeW: 0.28, sizeH: 0.37, cornerRadius: 0.015),
        layer1: LayerParams(originX: 0, originY: 0, sizeW: 0, sizeH: 0, cornerRadius: 0),
        layer2: LayerParams(originX: 0, originY: 0, sizeW: 0, sizeH: 0, cornerRadius: 0),
        layer3: LayerParams(originX: 0, originY: 0, sizeW: 0, sizeH: 0, cornerRadius: 0),
        activeCount: 1
    )

    init?() {
        assert(MemoryLayout<LayerParams>.size == 24, "LayerParams must be 24 bytes, got \(MemoryLayout<LayerParams>.size)")
        assert(MemoryLayout<CompositorParams>.size == 112, "CompositorParams must be 112 bytes, got \(MemoryLayout<CompositorParams>.size)")

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

    func configure(backWidth: Int, backHeight: Int, frontWidth: Int, frontHeight: Int) {
        let frontAspect = Float(frontWidth) / Float(frontHeight)
        let backAspect  = Float(backWidth)  / Float(backHeight)
        let pipW: Float = 0.28
        let pipH = pipW * backAspect / frontAspect
        let margin: Float = 0.03

        compositorParams.layer0 = LayerParams(
            originX: 1.0 - pipW - margin,
            originY: 1.0 - pipH - margin,
            sizeW: pipW,
            sizeH: pipH,
            cornerRadius: 0.015
        )
        compositorParams.activeCount = 1
    }

    func updateLayer(at index: Int, params: LayerParams) {
        switch index {
        case 0: compositorParams.layer0 = params
        case 1: compositorParams.layer1 = params
        case 2: compositorParams.layer2 = params
        case 3: compositorParams.layer3 = params
        default: break
        }
    }

    func setActiveLayerCount(_ count: Int) {
        compositorParams.activeCount = Int32(min(max(count, 0), 4))
    }

    // MARK: - 核心合成

    // overlays: [(buffer, layerIndex)] 对应 compositorParams.layers[layerIndex]
    func composite(backBuffer: CVPixelBuffer,
                   overlays: [(buffer: CVPixelBuffer, index: Int)]) -> CVPixelBuffer? {
        let w = CVPixelBufferGetWidth(backBuffer)
        let h = CVPixelBufferGetHeight(backBuffer)

        ensurePool(width: w, height: h)

        guard
            let outputBuffer = allocateOutputBuffer(),
            let backTex      = texture(from: backBuffer),
            let outputTex    = texture(from: outputBuffer)
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

        var metalParams = compositorParams
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(backTex, index: 0)

        // 绑定各层纹理到 texture(1)~texture(4)
        for overlay in overlays {
            let texIndex = overlay.index + 1  // index 0 → texture(1), etc.
            guard texIndex >= 1, texIndex <= 4,
                  let tex = texture(from: overlay.buffer) else { continue }
            encoder.setFragmentTexture(tex, index: texIndex)
        }

        encoder.setFragmentBytes(&metalParams, length: MemoryLayout<CompositorParams>.size, index: 0)
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
