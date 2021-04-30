import Metal
import MetalKit
import ARKit

let isDebugMode:Bool = false

let gridNodeCount:Int = Int(GRID_NODE_COUNT*GRID_NODE_COUNT)

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
    let device: MTLDevice
    let library: MTLLibrary
    let renderDestination: RenderDestinationProvider
    
    lazy private var relaxedStencilState: MTLDepthStencilState = {
        return device.makeDepthStencilState(descriptor: MTLDepthStencilDescriptor())!
    }()
    
    lazy private var depthStencilState: MTLDepthStencilState = {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .lessEqual
        descriptor.isDepthWriteEnabled = true
        return device.makeDepthStencilState(descriptor: descriptor)!
        
    }()
    
    let commandQueue: MTLCommandQueue
    
    private lazy var viewArea:MetalBuffer<CameraView> = {
        let viewCorners = [
            CameraView(viewVertices: [-1,1], viewTexCoords: [0,0]),
            CameraView(viewVertices: [-1,-1], viewTexCoords: [0,1]),
            CameraView(viewVertices: [1,1], viewTexCoords: [1,0]),
            CameraView(viewVertices: [1,-1], viewTexCoords: [1,1]),
        ]
        return .init(device: device, array:viewCorners, index: kViewCorner.rawValue)
    }()
    
//    private lazy var unprojectPipelineState = makeUnprojectionPipelineState()!
    private lazy var sphericalUnprojectPipelineState = makeSphericalUnprojectPipelineState()!
    private lazy var cartesianUnprojectPipelineState = makeCartesianUnprojectPipelineState()!
    private lazy var singleFrameUnprojectPipelineState = makeSingleFrameUnprojectPipelineState()!
    
//    private lazy var gridPipelineState = makeGridPipelineState()!
    private lazy var sphericalGridPipelineState = makeSphericalGridPipelineState()!
    private lazy var singleFramePipelineState = makeSingleFramePipelineState()!
    
    private lazy var heelMarkerAreaPipelineState = makeHeelMarkerAreaPipelineState()!
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
    
    
    lazy var gistroReductionState: MTLComputePipelineState = makeReductionComputeState()!
    lazy var toGistroConvertState: MTLComputePipelineState = makeConvertionComputeState()!
    var floorHeight:Float = -10
    
    
    // The current viewport size
    private var viewportSize = CGSize()
    // The grid of sample points
    private lazy var gridPointsBuffer = MetalBuffer<Float2>(device: device,
                                                            array: makeGridPoints(),
                                                            index: kGridPoints.rawValue, options: [])
    
    lazy var heelAreaMesh:MTKMesh = {
        let allocator = MTKMeshBufferAllocator(device: device)
        let height:Float = 0.002
        let radius:Float = 0.02
        let mdlMesh = MDLMesh(cylinderWithExtent: [radius, height, radius],
                                segments: [100,100],
                                inwardNormals: false,
                                topCap: true,
                                bottomCap: true,
                                geometryType: .triangles,
                                allocator: allocator)
        let mesh = try! MTKMesh(mesh: mdlMesh, device: device)
        
        return mesh
    }()
    
    private lazy var axisIndeces = MetalBuffer<UInt16>(device: device, array: makeAxisIndeces(), index: 0)
    
    func drawCameraStream(_ renderEncoder:MTLRenderCommandEncoder) {
        renderEncoder.setRenderPipelineState(cameraImageState)
        renderEncoder.setVertexBuffer(viewArea)
        renderEncoder.setVertexBytes(&viewToCamera, length: MemoryLayout<CGAffineTransform>.stride, index: Int(kViewToCam.rawValue))
        renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(capturedImageTextureY!), index: Int(kTextureY.rawValue))
        renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(capturedImageTextureCbCr!), index: Int(kTextureCbCr.rawValue))
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: viewArea.count)
    }
    
    func drawHeelMarker(_ renderEncoder:MTLRenderCommandEncoder) {
        renderEncoder.setRenderPipelineState(heelMarkerAreaPipelineState)
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
    }
    
    func drawScanningFootAsSphericalMesh(_ renderEncoder:MTLRenderCommandEncoder) {
        renderEncoder.setRenderPipelineState(sphericalGridPipelineState)
        renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
        
        renderEncoder.setVertexBuffer(myGridSphericalBuffer)
        renderEncoder.setVertexBytes(&floorHeight, length: MemoryLayout<Float>.stride, index: Int(kHeight.rawValue))
        renderEncoder.drawIndexedPrimitives(type: .triangleStrip,
                                            indexCount: myIndecesBuffer.count,
                                            indexType: .uint32,
                                            indexBuffer: myIndecesBuffer.buffer,
                                            indexBufferOffset: 0)
        
//        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: gridNodeCount)
    }
    
    func drawScanningFootAsSingleFrame(_ renderEncoder:MTLRenderCommandEncoder) {
        renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
        
        renderEncoder.setRenderPipelineState(singleFramePipelineState)
        
        renderEncoder.setVertexBuffer(myGridSphericalBuffer)
        
        renderEncoder.setVertexBytes(&floorHeight, length: MemoryLayout<Float>.stride, index: Int(kHeight.rawValue))
        renderEncoder.setVertexBytes(&frameAccumulated, length: MemoryLayout<Int32>.stride, index: Int(kFrame.rawValue))
        renderEncoder.drawIndexedPrimitives(type: .point,
                                            indexCount: myIndecesBuffer.count,
                                            indexType: .uint32,
                                            indexBuffer: myIndecesBuffer.buffer,
                                            indexBufferOffset: 0)
    }
    
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
    
    var gistrosBuffer:MTLBuffer!
    func initializeGistrosBuffer(nodeCount:Int) {
        gistrosBuffer = device.makeBuffer(length: MemoryLayout<Gistro>.stride*nodeCount)
    }
    
    
    var frameAccumulated: Int32 = 0;
    
    var currentState:RendererState {
        willSet {
            switch newValue {
            case .findFootArea:
                frameAccumulated = 0
                floorHeight = -10
                initializeGridNodes(nodeCount: gridNodeCount)
            case .scanning:
                initializeSphericalGridNodes(nodeCount: gridNodeCount)
            case .separate:
                frameAccumulated = 0
                initializeSphericalGridNodes(nodeCount: gridNodeCount)
            }
        }
    }
    
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
        currentState = .findFootArea
        initializeGridNodes(nodeCount: gridNodeCount)
        initializeGistrosBuffer(nodeCount: gridNodeCount)
    }
    
    func initializeGridNodes(nodeCount:Int) {
        let initVal = initMyMeshData(-0.5)
        let gridInitial = Array(repeating: initVal, count: nodeCount)
        myGridBuffer = .init(device: device, array:gridInitial, index: kMyMesh.rawValue)
//		for i in 0..<myGridBuffer.count {
//			print(i)
//			debugNode(node: i, buffer: myGridBuffer.buffer, field: .pairLen)
//		}
//		print(nodeCount, myGridBuffer.count)
    }
    
    func initializeSphericalGridNodes(nodeCount:Int) {
        let initVal = initMyMeshData(0)
        let gridInitial = Array(repeating: initVal, count: nodeCount)
        myGridSphericalBuffer = .init(device: device, array:gridInitial, index: kMyMesh.rawValue)
    }
    
    
	func initializeGridIndeces(cyclic:Bool = true) -> MetalBuffer<UInt32> {
        
        var indecesData = [UInt32]()
        let nodeCount = UInt32(GRID_NODE_COUNT)

        func index(_ i:UInt32, _ j:UInt32) -> UInt32 {
            return i*nodeCount + j
        }

        func UpDown(_ j: UInt32) -> [UInt32] {
            var res = [UInt32]()
            for i in 0..<nodeCount-1 {
                res.append( contentsOf: [index(i,j), index(i,j+1)] )
            }
            res.append(index(nodeCount-1,j))

            return res
        }

        func DownUp(_ j: UInt32) -> [UInt32] {

            var res = [UInt32]()
            for i in (1..<nodeCount).reversed() {
				if cyclic {
					res.append(contentsOf: [index(i, j%nodeCount), index(i,(j+1)%nodeCount)])
				} else {
					res.append(contentsOf: [index(i, j), index(i,j+1)])
				}
                
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

		let cyclicNode:UInt32 = cyclic ? 1: 0
        let endPoint:()->UInt32 = ((nodeCount + cyclicNode)%2 == 0) ? bottomRight : upRight

        for j in 0..<nodeCount-1 + cyclicNode {
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
    
    func gpuSeparate(floorInit: Float) -> Float {
        
        let minCountOfNodes = Int(0.02*Double(myGridBuffer.count))
        
//        var startTime, endTime: CFAbsoluteTime
        
        let delta = Float(1e-3)
        var interval = Float2()
        if floorInit != -10 {
            interval = Float2(floorInit + 0.75*delta, floorInit - 0.75*delta);
        } else {
            interval = Float2(0, -2)
        }
//        var i:Int = 1
        
        while interval.x - interval.y > delta {
            // генерация массива Gistro для каждого узла
            makeConversion(bufferIn: myGridBuffer.buffer, bufferOut: &gistrosBuffer, &interval)

            let resGistro:Gistro = reductionGistrosData(gistrosBuffer)!
            
            let c = (interval.x + interval.y)*0.5
            if (resGistro.mn.max() < minCountOfNodes) {
                return floorInit
            }
            if resGistro.mn[0] > resGistro.mn[1] {
                interval.y = c
            } else {
                interval.x = c
            }
//            i += 1
            if interval.x - interval.y <= delta {
                print("   (\(resGistro.mn[0]), \(resGistro.mn[1]))")
            }
        }
		return (interval.x + interval.y)*0.5
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
        
        if currentState == .findFootArea {
            if frameAccumulated > 10 {
                if ( frameAccumulated%10 == 0 ) {
                    floorHeight = gpuSeparate(floorInit: floorHeight)
                    print(" floor \(floorHeight)")
                }
            }
        }
                      
        if canUpdateDepthTextures(frame: currentFrame) {
            accumulatePoints(frame: currentFrame, commandBuffer: commandBuffer, renderEncoder: renderEncoder)
//			for i in 0..<myGridBuffer.count {
//				print(i)
//				debugNode(node: i, buffer: myGridBuffer.buffer, field: .pairLen)
//			}
//			print("")

			
        }
        
        switch currentState {
        case .findFootArea:
			
//			for i in 0..<myGridBuffer.count {
//				print(i)
//				debugNode(node: i, buffer: myGridBuffer.buffer, field: .pairLen)
//			}
			
            updateCapturedImageTextures(frame: currentFrame)
            renderEncoder.setDepthStencilState(relaxedStencilState)
            drawCameraStream(renderEncoder)
            drawHeelMarker(renderEncoder)
        case .scanning:
            renderEncoder.setDepthStencilState(depthStencilState)
            drawScanningFootAsSphericalMesh(renderEncoder)
        case .separate:
            renderEncoder.setDepthStencilState(depthStencilState)
            drawScanningFootAsSingleFrame(renderEncoder)
        }
    
        renderEncoder.endEncoding()
        commandBuffer.present(renderDestination.currentDrawable!)
        commandBuffer.commit()
    }
    
    private func accumulatePoints(frame: ARFrame,
                                  commandBuffer: MTLCommandBuffer,
                                  renderEncoder: MTLRenderCommandEncoder) {

        var retainingTextures = [
            depthTexture,
            confidenceTexture]
        commandBuffer.addCompletedHandler { buffer in
            retainingTextures.removeAll()
        }
        
        switch currentState {
        case .findFootArea:
            renderEncoder.setRenderPipelineState(cartesianUnprojectPipelineState)
            renderEncoder.setVertexBuffer(myGridBuffer)
            frameAccumulated += 1
        case .scanning:
            renderEncoder.setRenderPipelineState(sphericalUnprojectPipelineState)
            renderEncoder.setVertexBuffer(myGridSphericalBuffer)
        case .separate:
            if frameAccumulated >= MAX_MESH_STATISTIC-1 {
//                frameAccumulated = 0
                return
            }
            
            renderEncoder.setRenderPipelineState(singleFrameUnprojectPipelineState)
            renderEncoder.setVertexBuffer(myGridSphericalBuffer)
            renderEncoder.setVertexBytes(&frameAccumulated, length: MemoryLayout<Int32>.stride, index: Int(kFrame.rawValue))
            
            print("frame accumulated: \(frameAccumulated)")
            frameAccumulated += 1
        }
        
        renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
        renderEncoder.setVertexBuffer(gridPointsBuffer)
        renderEncoder.setVertexBytes(&floorHeight, length: MemoryLayout<Float>.stride, index: Int(kHeight.rawValue))
        renderEncoder.setVertexTexture(CVMetalTextureGetTexture(depthTexture!), index: Int(kTextureDepth.rawValue))
        renderEncoder.setVertexTexture(CVMetalTextureGetTexture(confidenceTexture!), index: Int(kTextureConfidence.rawValue))
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: gridPointsBuffer.count)
		
		
//		if currentState == .scanning {
//			var problem:[Int32] = .init()
//			var problemWaite:[Int32] = .init()
//			for node in 0..<myGridSphericalBuffer.count {
//				let pp = myGridSphericalBuffer.buffer.contents().load(fromByteOffset: MemoryLayout<MyMeshData>.stride*node, as: MyMeshData.self)
//				problem.append(pp.pairLen)
//				problemWaite.append(pp.debugCall)
//			}
			
//			problem.sort()
//			for pr in problem {
//				if pr > 80 {
//					print(pr)
//				}
//			}
//			problemWaite.sort()
//			for pr in problemWaite {
//				if pr > 0 {
//					print("debugCall \(pr)")
//				}
//			}
//		}

        
        lastCameraTransform = frame.camera.transform
    }
}

private extension Renderer {
	
	/// Makes sample points on camera image, also precompute the anchor point for animation
	func makeGridPoints() -> [Float2] {
		let numGridPoints = 250_000;
		let gridArea = cameraResolution.x * cameraResolution.y
		let spacing = sqrt(gridArea / Float(numGridPoints))
		let deltaX = Int(round(cameraResolution.x / spacing))
		let deltaY = Int(round(cameraResolution.y / spacing))
		
		var points = [Float2]()
		for gridY in 0 ..< deltaY {
			let alternatingOffsetX = Float(gridY % 2) * spacing / 2
			for gridX in 0 ..< deltaX {
				let cameraPoint = Float2(alternatingOffsetX + (Float(gridX) + 0.5) * spacing, (Float(gridY) + 0.5) * spacing)
				
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
	
	
	func getCamNormal() -> Float3 {
		
		return Float3();
	}
	
}
