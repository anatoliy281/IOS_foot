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
    
    private lazy var cartesianGridPipelineState = makeCartesianGridPipelineState()!
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
		
		let url = Bundle.main.url(forResource: "fittin", withExtension: "obj")!

		let vertexDescriptor = MTLVertexDescriptor()
		vertexDescriptor.attributes[0].format = .float3
		vertexDescriptor.attributes[0].offset = 0
		vertexDescriptor.attributes[0].bufferIndex = 0
		vertexDescriptor.layouts[0].stride = MemoryLayout<Float3>.stride

		let meshDescriptor = MTKModelIOVertexDescriptorFromMetal(vertexDescriptor)
		(meshDescriptor.attributes[0] as! MDLVertexAttribute).name = MDLVertexAttributePosition



		let asset = MDLAsset( url: url,
							 vertexDescriptor: meshDescriptor,
							 bufferAllocator: MTKMeshBufferAllocator(device: device) )

		let mdlMesh = asset.object(at: 0) as! MDLMesh

		return try! MTKMesh(mesh: mdlMesh, device: device)
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
    
	func drawMesh(gridType:Int, _ renderEncoder:MTLRenderCommandEncoder) {
		var state: MTLRenderPipelineState
		var buffer: MetalBuffer<MyMeshData>
		if gridType == 1 { // Spherical
			state = sphericalGridPipelineState
			buffer = sphericalGridBuffer
		} else {
			state = cartesianGridPipelineState
			buffer = cartesianGridBuffer
		}
        renderEncoder.setRenderPipelineState(state)
        renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
        renderEncoder.setVertexBuffer(buffer)
        renderEncoder.setVertexBytes(&floorHeight, length: MemoryLayout<Float>.stride, index: Int(kHeight.rawValue))
		if gridType == 0 {
			renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: gridNodeCount)
		} else {
			renderEncoder.drawIndexedPrimitives(type: .triangleStrip,
												indexCount: indecesBuffer.count,
												indexType: .uint32,
												indexBuffer: indecesBuffer.buffer,
												indexBufferOffset: 0)
		}

    }
    
    func drawScanningFootAsSingleFrame(_ renderEncoder:MTLRenderCommandEncoder) {
        renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
        
        renderEncoder.setRenderPipelineState(singleFramePipelineState)
        
        renderEncoder.setVertexBuffer(sphericalGridBuffer)
        
        renderEncoder.setVertexBytes(&floorHeight, length: MemoryLayout<Float>.stride, index: Int(kHeight.rawValue))
        renderEncoder.setVertexBytes(&frameAccumulated, length: MemoryLayout<Int32>.stride, index: Int(kFrame.rawValue))
        renderEncoder.drawIndexedPrimitives(type: .point,
                                            indexCount: indecesBuffer.count,
                                            indexType: .uint32,
                                            indexBuffer: indecesBuffer.buffer,
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
    
    
    var cartesianGridBuffer: MetalBuffer<MyMeshData>!
	lazy var indecesBuffer: MetalBuffer<UInt32> = initializeGridIndeces()
    
    var sphericalGridBuffer: MetalBuffer<MyMeshData>!
    
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
        let initVal = initMyMeshData(-2)
        let gridInitial = Array(repeating: initVal, count: nodeCount)
        cartesianGridBuffer = .init(device: device, array:gridInitial, index: kMyMesh.rawValue)
    }
    
    func initializeSphericalGridNodes(nodeCount:Int) {
        let initVal = initMyMeshData(0)
        let gridInitial = Array(repeating: initVal, count: nodeCount)
        sphericalGridBuffer = .init(device: device, array:gridInitial, index: kMyMesh.rawValue)
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
        indecesBuffer = .init(device: device, array: indecesData, index: 0)
        
        return indecesBuffer
        
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
    
	
	func cpuCalcFloor() -> Double {
		var sum:Double = 0
		var count:Double = 0
		for i in 0..<cartesianGridBuffer.count {
			if cartesianGridBuffer[i].group == Floor {
				sum += Double(cartesianGridBuffer[i].median)
				count += Double(1)
			}
		}
		if (count == 0) {
			return -10;
		}
		return sum / count
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
        
//        if currentState == .findFootArea {
//            if frameAccumulated > 10 {
		let nc:Int32 = 10
		if ( frameAccumulated%nc == 0 && frameAccumulated != 0 ) {
			floorHeight = Float(cpuCalcFloor())
//			print("\(frameAccumulated/nc) floor \(floorHeight)")
		}
                      
        if canUpdateDepthTextures(frame: currentFrame) {
            accumulatePoints(frame: currentFrame, commandBuffer: commandBuffer, renderEncoder: renderEncoder)
//			for i in 0..<myGridBuffer.count {
//				print(i)
//				debugNode(node: i, buffer: myGridBuffer.buffer, field: .pairLen)
//			}
//			print("")

			
        }
		renderEncoder.setDepthStencilState(relaxedStencilState)
		updateCapturedImageTextures(frame: currentFrame)
		drawCameraStream(renderEncoder)
		switch currentState {
        case .findFootArea:
            drawHeelMarker(renderEncoder)
        case .scanning:
            renderEncoder.setDepthStencilState(depthStencilState)
            drawMesh(gridType: 0, renderEncoder) 	// cartesian
			drawMesh(gridType: 1, renderEncoder)	// spherical
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
        
		renderEncoder.setRenderPipelineState(cartesianUnprojectPipelineState)
		renderEncoder.setVertexBuffer(cartesianGridBuffer)
		renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
		renderEncoder.setVertexBuffer(gridPointsBuffer)
		renderEncoder.setVertexBytes(&floorHeight, length: MemoryLayout<Float>.stride, index: Int(kHeight.rawValue))
		renderEncoder.setVertexTexture(CVMetalTextureGetTexture(depthTexture!), index: Int(kTextureDepth.rawValue))
		renderEncoder.setVertexTexture(CVMetalTextureGetTexture(confidenceTexture!), index: Int(kTextureConfidence.rawValue))
		renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: gridPointsBuffer.count)
		
		frameAccumulated += 1
		if currentState == .scanning {
            renderEncoder.setRenderPipelineState(sphericalUnprojectPipelineState)
            renderEncoder.setVertexBuffer(sphericalGridBuffer)
			renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
			renderEncoder.setVertexBuffer(gridPointsBuffer)
			renderEncoder.setVertexBytes(&floorHeight, length: MemoryLayout<Float>.stride, index: Int(kHeight.rawValue))
			renderEncoder.setVertexTexture(CVMetalTextureGetTexture(depthTexture!), index: Int(kTextureDepth.rawValue))
			renderEncoder.setVertexTexture(CVMetalTextureGetTexture(confidenceTexture!), index: Int(kTextureConfidence.rawValue))
			renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: gridPointsBuffer.count)
		} else if currentState == .separate {
            if frameAccumulated >= MAX_MESH_STATISTIC-1 {
//                frameAccumulated = 0
                return
            }
            
            renderEncoder.setRenderPipelineState(singleFrameUnprojectPipelineState)
            renderEncoder.setVertexBuffer(sphericalGridBuffer)
            renderEncoder.setVertexBytes(&frameAccumulated, length: MemoryLayout<Int32>.stride, index: Int(kFrame.rawValue))
            
            print("frame accumulated: \(frameAccumulated)")
		} else {}
      
		
	
        
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
