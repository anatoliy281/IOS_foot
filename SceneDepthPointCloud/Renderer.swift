import Metal
import MetalKit
import ARKit

enum RendererState {
    case findFootArea
    case scanning
}

class Renderer {
    
    private let orientation = UIInterfaceOrientation.landscapeRight
    // Camera's threshold values for detecting when the camera moves so that we can accumulate the points
    private let cameraRotationThreshold = cos(2 * .degreesToRadian)
    private let cameraTranslationThreshold: Float = pow(0.02, 2)   // (meter-squared)
    // The max number of command buffers in flight
    private let maxInFlightBuffers = 3
    
    private lazy var rotateToARCamera = Self.makeRotateToARCameraMatrix(orientation: orientation)
    private let session: ARSession
    
    // Metal objects and textures
    private let device: MTLDevice
    private let library: MTLLibrary
    private let renderDestination: RenderDestinationProvider
    
    lazy private var relaxedStencilState: MTLDepthStencilState = {
        return device.makeDepthStencilState(descriptor: MTLDepthStencilDescriptor())!
    }()
    
    lazy private var depthStencilState: MTLDepthStencilState = {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .lessEqual
        descriptor.isDepthWriteEnabled = true
        return device.makeDepthStencilState(descriptor: descriptor)!
        
    }()
    
    private let commandQueue: MTLCommandQueue
    
    private lazy var viewArea:MetalBuffer<CameraView> = {
        let viewCorners = [
            CameraView(viewVertices: [-1,1], viewTexCoords: [0,0]),
            CameraView(viewVertices: [-1,-1], viewTexCoords: [0,1]),
            CameraView(viewVertices: [1,1], viewTexCoords: [1,0]),
            CameraView(viewVertices: [1,-1], viewTexCoords: [1,1]),
        ]
        return .init(device: device, array:viewCorners, index: kViewCorner.rawValue)
    }()
    
    private lazy var unprojectPipelineState = makeUnprojectionPipelineState()!
    
    private lazy var gridPipelineState = makeGridPipelineState()!
    private lazy var axisPipelineState = makeAxisPipelineState()!
    private lazy var cameraImageState = makeCameraImageState()!
    
    // texture cache for captured image
    private lazy var textureCache = makeTextureCache()
    private var depthTexture: CVMetalTexture?
    private var confidenceTexture: CVMetalTexture?
    private var capturedImageTextureY: CVMetalTexture?
    private var capturedImageTextureCbCr: CVMetalTexture?
    
    // Multi-buffer rendering pipeline
    private let inFlightSemaphore: DispatchSemaphore
    private var currentBufferIndex = 0
    
    var floorHeight:Float = -10
    
    
    // The current viewport size
    private var viewportSize = CGSize()
    // The grid of sample points
    private lazy var gridPointsBuffer = MetalBuffer<Float2>(device: device,
                                                            array: makeGridPoints(),
                                                            index: kGridPoints.rawValue, options: [])
    
    private lazy var heelAreaMesh:MTKMesh = {
        let allocator = MTKMeshBufferAllocator(device: device)
        let height:Float = 0.05
        let radius:Float = 0.02
        let mdlMesh = MDLMesh(cylinderWithExtent: [radius, height, radius],
                                segments: [100,100],
                                inwardNormals: false,
                                topCap: false,
                                bottomCap: false,
                                geometryType: .triangles,
                                allocator: allocator)
        let mesh = try! MTKMesh(mesh: mdlMesh, device: device)
        return mesh
    }()
    
    private lazy var axisIndeces = MetalBuffer<UInt16>(device: device, array: makeAxisIndeces(), index: 0)
    
    // Point Cloud buffer
    private lazy var pointCloudUniforms: PointCloudUniforms = {
        var uniforms = PointCloudUniforms()
        uniforms.cameraResolution = cameraResolution
        return uniforms
    }()
    private var pointCloudUniformsBuffers = [MetalBuffer<PointCloudUniforms>]()
    
    // Camera data
    private var sampleFrame: ARFrame { session.currentFrame! }
    private lazy var cameraResolution = Float2(Float(sampleFrame.camera.imageResolution.width), Float(sampleFrame.camera.imageResolution.height))
    
    private lazy var viewToCamera:matrix_float3x3 = {
        var mat = matrix_float3x3()
        mat.copy(from: sampleFrame.displayTransform(for: orientation, viewportSize: viewportSize).inverted())
        return mat
    }()
    private lazy var lastCameraTransform = sampleFrame.camera.transform
    
    
    var myGridBuffer: MetalBuffer<MyMeshData>!
    lazy var myIndecesBuffer: MetalBuffer<UInt32> = initializeGridIndeces()
    
    var myGridSphericalBuffer: MetalBuffer<MyMeshData>!
    
    
    var frameAccumulated: UInt = 0;
    var frameEnoughForHeight: UInt = 10
    
    var state:RendererState
    
    init(session: ARSession, metalDevice device: MTLDevice, renderDestination: RenderDestinationProvider) {
        self.session = session
        self.device = device
        self.renderDestination = renderDestination
        
        library = device.makeDefaultLibrary()!
        commandQueue = device.makeCommandQueue()!
        
        // initialize our buffers
        for _ in 0 ..< maxInFlightBuffers {
            pointCloudUniformsBuffers.append(.init(device: device, count: 1, index: kPointCloudUniforms.rawValue))
        }
        
        inFlightSemaphore = DispatchSemaphore(value: maxInFlightBuffers)
        state = .findFootArea
        initializeGridNodes()
    }
    
    func setState(state newState:RendererState) {
        state = newState
    }
    
    func initializeGridNodes() {
        let initVal = initMyMeshData()
        let gridInitial = Array(repeating: initVal, count: Int(GRID_NODE_COUNT*GRID_NODE_COUNT))
        myGridBuffer = .init(device: device, array:gridInitial, index: kMyMesh.rawValue)
    }
    
    func initializeSphericalGridNodes() {
        let initVal = initMyMeshData()
        let gridInitial = Array(repeating: initVal, count: Int(GRID_NODE_COUNT*GRID_NODE_COUNT))
        myGridSphericalBuffer = .init(device: device, array:gridInitial, index: kMyMesh.rawValue)
    }
    
    
    func initializeGridIndeces() -> MetalBuffer<UInt32> {
        
        var indecesData = [UInt32]()
        let nodeCount = UInt32(GRID_NODE_COUNT)

        func index(_ i:UInt32, _ j:UInt32) -> UInt32 {
            return i*nodeCount + j
        }

        func UpDown(_ j: UInt32) -> [UInt32] {

            var res = [UInt32]()
            for i in 0..<nodeCount-1 {
                res.append(contentsOf: [index(i,j), index(i,j+1)])
            }
            res.append(index(nodeCount-1,j))

            return res

        }

        func DownUp(_ j: UInt32) -> [UInt32] {

            var res = [UInt32]()
            for i in (1..<nodeCount).reversed() {
                res.append(contentsOf: [index(i,j), index(i,j+1)])
            }
            res.append(index(0,j))

            return res

        }

        func bottomRight() -> UInt32 {
            return index(nodeCount-1, nodeCount-1)
        }

        func upRight() -> UInt32 {
            return index(0, nodeCount-1)
        }


        let endPoint:()->UInt32 = (nodeCount%2 == 0) ? bottomRight : upRight

        for j in 0..<nodeCount-1 {
            let move:(UInt32)->[UInt32] = (j%2 == 0) ? UpDown : DownUp
            indecesData.append(contentsOf: move(j))
        }
        indecesData.append(endPoint())
        myIndecesBuffer = .init(device: device, array: indecesData, index: 0)
        
        return myIndecesBuffer
        
    }
    
    func drawRectResized(size: CGSize) {
        viewportSize = size
    }
   
    
    private func canUpdateDepthTextures(frame: ARFrame) -> Bool {
        guard let depthMap = frame.sceneDepth?.depthMap,
            let confidenceMap = frame.sceneDepth?.confidenceMap else {
                return false
        }
        
        depthTexture = makeTexture(fromPixelBuffer: depthMap, pixelFormat: .r32Float, planeIndex: 0)
        confidenceTexture = makeTexture(fromPixelBuffer: confidenceMap, pixelFormat: .r8Uint, planeIndex: 0)
        
        return true
    }
    
    private func updateCapturedImageTextures(frame: ARFrame) {
        let pixelBuffer = frame.capturedImage
        guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 2 else {
            return
        }
        capturedImageTextureY = makeTexture(fromPixelBuffer: pixelBuffer, pixelFormat: .r8Unorm, planeIndex: 0)
        capturedImageTextureCbCr = makeTexture(fromPixelBuffer: pixelBuffer, pixelFormat: .rg8Unorm, planeIndex: 1)
    }
    
    private func update(frame: ARFrame) {
        // frame dependent info
        let camera = frame.camera
        let cameraIntrinsicsInversed = camera.intrinsics.inverse
        let viewMatrix = camera.viewMatrix(for: orientation)
        let viewMatrixInversed = viewMatrix.inverse
        let projectionMatrix = camera.projectionMatrix(for: orientation, viewportSize: viewportSize, zNear: 0.001, zFar: 0)
        pointCloudUniforms.viewProjectionMatrix = projectionMatrix * viewMatrix
        pointCloudUniforms.localToWorld = viewMatrixInversed * rotateToARCamera
        pointCloudUniforms.cameraIntrinsicsInversed = cameraIntrinsicsInversed
    }
    
    func separate()  {
        let dH:Float = 2e-3;
        
        func calcHeightGistro() -> [Float:Int] {
            var res = [Float:Int]()
            let grid = myGridBuffer!
            for i in 0..<grid.count {
                let nodeStat = grid[i]
                if nodeStat.length == 0 { continue }
                let h = getMedian(nodeStat)
                let hDescr = floor(h/dH)*dH
                if let cnt = res[hDescr] {
                    res[hDescr] = cnt + 1
                } else {
                    res[hDescr] = 1
                }
            }
            return res
        }
        
        
        func findFloor(_ gistro: [Float:Int]) -> Float {
            let floorHeight = gistro.max {
                return $0.1 < $1.1
            }
            return floorHeight!.0
        }
        
        let gistro = calcHeightGistro()
        if !gistro.isEmpty {
            floorHeight = findFloor( gistro )
        }
    }
    
    
    
    func draw() {
        guard let currentFrame = session.currentFrame,
            let renderDescriptor = renderDestination.currentRenderPassDescriptor,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderDescriptor) else {
                return
        }
        
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        commandBuffer.addCompletedHandler { [weak self] commandBuffer in
            if let self = self {
                self.inFlightSemaphore.signal()
            }
        }
        
        // update frame data
        update(frame: currentFrame)
        
        currentBufferIndex = (currentBufferIndex + 1) % maxInFlightBuffers
        pointCloudUniformsBuffers[currentBufferIndex][0] = pointCloudUniforms
        
        if canUpdateDepthTextures(frame: currentFrame) {
            frameAccumulated += 1
            accumulatePoints(frame: currentFrame, commandBuffer: commandBuffer, renderEncoder: renderEncoder)
        }
        
        if state == .findFootArea {
            updateCapturedImageTextures(frame: currentFrame)
            renderEncoder.setDepthStencilState(relaxedStencilState)
            
            renderEncoder.setRenderPipelineState(cameraImageState)
            renderEncoder.setVertexBuffer(viewArea)
            renderEncoder.setVertexBytes(&viewToCamera, length: MemoryLayout<CGAffineTransform>.stride, index: Int(kViewToCam.rawValue))
            renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(capturedImageTextureY!), index: Int(kTextureY.rawValue))
            renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(capturedImageTextureCbCr!), index: Int(kTextureCbCr.rawValue))
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: viewArea.count)
            
            renderEncoder.setRenderPipelineState(axisPipelineState)
            renderEncoder.setVertexBuffer(heelAreaMesh.vertexBuffers[0].buffer,
                                          offset: 0,
                                          index: Int(kHeelArea.rawValue))
            renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
            renderEncoder.setVertexBytes(&floorHeight, length: MemoryLayout<Float>.stride, index: Int(kHeight.rawValue))
            
            guard let submesh = heelAreaMesh.submeshes.first else { return }
            renderEncoder.drawIndexedPrimitives(type: .triangle,
                                                indexCount: submesh.indexCount,
                                                indexType: submesh.indexType,
                                                indexBuffer: submesh.indexBuffer.buffer,
                                                indexBufferOffset: submesh.indexBuffer.offset)
        } else {
            // handle buffer rotating
            renderEncoder.setDepthStencilState(depthStencilState)
            
            renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
            
            renderEncoder.setRenderPipelineState(gridPipelineState)
            
            renderEncoder.setVertexBuffer(myGridSphericalBuffer)
            renderEncoder.setVertexBytes(&floorHeight, length: MemoryLayout<Float>.stride, index: Int(kHeight.rawValue))
            renderEncoder.drawIndexedPrimitives(type: .triangleStrip,
                                                indexCount: myIndecesBuffer.count,
                                                indexType: .uint32,
                                                indexBuffer: myIndecesBuffer.buffer,
                                                indexBufferOffset: 0)
        }
        
        renderEncoder.endEncoding()
        commandBuffer.present(renderDestination.currentDrawable!)
        commandBuffer.commit()
        
        if (frameAccumulated%10 == 0) && (floorHeight == -10) {
            separate()
        }
    }
    
    private func accumulatePoints(frame: ARFrame, commandBuffer: MTLCommandBuffer, renderEncoder: MTLRenderCommandEncoder) {

        var retainingTextures = [
            depthTexture,
            confidenceTexture]
        commandBuffer.addCompletedHandler { buffer in
            retainingTextures.removeAll()
        }
        renderEncoder.setRenderPipelineState(unprojectPipelineState)
        renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
        renderEncoder.setVertexBuffer(gridPointsBuffer)
        
        if state == .findFootArea {
            renderEncoder.setVertexBuffer(myGridBuffer)
        } else {
            renderEncoder.setVertexBuffer(myGridSphericalBuffer)
        }
        renderEncoder.setVertexBytes(&floorHeight, length: MemoryLayout<Float>.stride, index: Int(kHeight.rawValue))

        renderEncoder.setVertexTexture(CVMetalTextureGetTexture(depthTexture!), index: Int(kTextureDepth.rawValue))
        renderEncoder.setVertexTexture(CVMetalTextureGetTexture(confidenceTexture!), index: Int(kTextureConfidence.rawValue))
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: gridPointsBuffer.count)
        
        lastCameraTransform = frame.camera.transform
    }
}

private extension Renderer {
    func makeUnprojectionPipelineState() -> MTLRenderPipelineState? {
        guard let vertexFunction = library.makeFunction(name: "unprojectVertex") else {
            return nil
        }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.isRasterizationEnabled = false
        descriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        descriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    func makeGridPipelineState() -> MTLRenderPipelineState? {
        guard let vertexFunction = library.makeFunction(name: "gridVertex"),
              let fragmentFunction = library.makeFunction(name: "gridFragment") else { return nil }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat

        descriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    func makeAxisPipelineState() -> MTLRenderPipelineState? {
        guard let vertexFunction = library.makeFunction(name: "axisVertex"),
              let fragmentFunction = library.makeFunction(name: "axisFragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        descriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        descriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(heelAreaMesh.vertexDescriptor)
        
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    func makeCameraImageState() -> MTLRenderPipelineState? {
        guard let vertexFunction = library.makeFunction(name: "cameraImageVertex"),
              let fragmentFunction = library.makeFunction(name: "cameraImageFragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        descriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
//        descriptor.colorAttachments[0].isBlendingEnabled = true
        
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    func makePointCloudState() -> MTLRenderPipelineState? {
        guard let vertexFunction = library.makeFunction(name: "particleVertex"),
              let fragmentFunction = library.makeFunction(name: "particleFragment") else { return nil }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat

        descriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    /// Makes sample points on camera image, also precompute the anchor point for animation
    func makeGridPoints() -> [Float2] {
        let deltaX = Int(round(cameraResolution.x))
        let deltaY = Int(round(cameraResolution.y))
        
        var points = [Float2]()
        for gridY in 0 ..< deltaY {
            let alternatingOffsetX = Float(gridY % 2) / 2
            for gridX in 0 ..< deltaX {
                let cameraPoint = Float2(alternatingOffsetX + (Float(gridX) + 0.5), (Float(gridY) + 0.5))
                
                points.append(cameraPoint)
            }
        }
        
        return points
    }
    
    
    func makeAxisIndeces() -> [UInt16] {
        let zero = UInt16(0)
        return [zero, UInt16(1),
                zero, UInt16(2),
                zero, UInt16(3),
        ]
    }
    
    func makeTextureCache() -> CVMetalTextureCache {
        // Create captured image texture cache
        var cache: CVMetalTextureCache!
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        
        return cache
    }
    
    func makeTexture(fromPixelBuffer pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat, planeIndex: Int) -> CVMetalTexture? {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        
        var texture: CVMetalTexture? = nil
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer, nil, pixelFormat, width, height, planeIndex, &texture)
        
        if status != kCVReturnSuccess {
            texture = nil
        }

        return texture
    }
    
    static func cameraToDisplayRotation(orientation: UIInterfaceOrientation) -> Int {
        switch orientation {
        case .landscapeLeft:
            return 180
        case .portrait:
            return 90
        case .portraitUpsideDown:
            return -90
        default:
            return 0
        }
    }
    
    static func makeRotateToARCameraMatrix(orientation: UIInterfaceOrientation) -> matrix_float4x4 {
        // flip to ARKit Camera's coordinate
        let flipYZ = matrix_float4x4(
            [1, 0, 0, 0],
            [0, -1, 0, 0],
            [0, 0, -1, 0],
            [0, 0, 0, 1] )

        let rotationAngle = Float(cameraToDisplayRotation(orientation: orientation)) * .degreesToRadian
        return flipYZ * matrix_float4x4(simd_quaternion(rotationAngle, Float3(0, 0, 1)))
    }
}
