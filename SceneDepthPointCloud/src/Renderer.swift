import Metal
import MetalKit
import ARKit

let isMeasuringMode:Bool = false


let gridCartesianNodeCount:Int = Int(GRID_NODE_COUNT*GRID_NODE_COUNT)
let gridCurveNodeCount:Int = Int(U_GRID_NODE_COUNT*PHI_GRID_NODE_COUNT)

class Renderer {
	
	struct InertialFloat3 {
		private var curLen:Int
		private let maxLen:Int
		private var points:[Float3]
		
		init() {
			curLen = 0
			maxLen = 32
			points = .init(repeating: .zero, count: maxLen)
		}
		
		var mean:Float3 {
			get {
				var res:Float3 = .zero
				let sz = min(curLen, maxLen)
				for i in 0..<sz {
					res += points[i]
				}
				return res / Float(sz)
			}
			
			set {
				curLen += 1
				points[curLen%maxLen] = newValue
			}
		}
		
		mutating func reset()  {
			for i in 0..<points.count {
				points[i] = .zero
				curLen = 0
			}
		}
	}
	
	// Метрические характеристики ноги
	struct FootMetricProps {
		var length: (a:InertialFloat3, b:InertialFloat3)
		var bunchWidth: (a:InertialFloat3, b:InertialFloat3, c:InertialFloat3)
		var interval: (a:InertialFloat3, b:InertialFloat3)
		var heightInRise: InertialFloat3
		var basis: (el:Float3, en:Float3) 	// базис связанный с ногой. el ориентирована вдоль ноги, en - по нормали, el, en переходит в исходную систему при соответствующих поворотах
	}

	enum MetricMode: Int {
		case lengthToe = 0,
			 lengthHeel = 1,
			 bunchWidthOuter = 2,
			 bunchWidthInner = 3,
			 heightInRise = 4
	}
	
	
	
	var metricMode:MetricMode = .lengthToe {
		willSet {
			
			footMetric.interval.a.reset()
			footMetric.interval.b.reset()
			metricPoints[0].typePoint = metric
			metricPoints[1].typePoint = camera
			metricPoints[7].typePoint = interval
			metricPoints[8].typePoint = interval
			
			switch(newValue) {
			case .lengthToe:
				metricPoints[9].typePoint = none
				// disable bunch
				metricPoints[6].typePoint = none
				metricPoints[5].typePoint = none
				metricPoints[4].typePoint = none
				// enable length
				metricPoints[2].typePoint = metricNow // toe
			case .lengthHeel:
				metricPoints[2].typePoint = metric
				metricPoints[3].typePoint = metricNow	// heel
			case .bunchWidthOuter:
				// disable length marks
				metricPoints[2].typePoint = none
				metricPoints[3].typePoint = none
				// bunch
				metricPoints[4].typePoint = metricNow // left bunch width
				metricPoints[6].typePoint = metricNow // toe for bunch
			case .bunchWidthInner:
				metricPoints[4].typePoint = metric		// left bunch point
				metricPoints[5].typePoint = metricNow	// right bunch point
			case .heightInRise:
				metricPoints[5].typePoint = none		// right bunch point
				metricPoints[9].typePoint = metricNow	// height in rise
			}
		}
	}
	
	var camPosition:simd_float3 = .zero {
		willSet{
			metricPoints[0].mean = .zero // центр ЛКС
			metricPoints[1].mean = newValue
		}
	}
	
	func nextMetricStep() {
		if metricMode == .lengthToe {
			metricMode = .lengthHeel
		} else if metricMode == .lengthHeel {
			metricMode = .bunchWidthOuter
		} else if metricMode == .bunchWidthOuter {
			metricMode = .bunchWidthInner
		} else if metricMode == .bunchWidthInner {
			metricMode = .heightInRise
		} else {
			metricMode = .lengthToe
		}
	}
	
	var footMetric:FootMetricProps {
		willSet {
			metricPoints[2].mean = newValue.length.a.mean
			metricPoints[3].mean = newValue.length.b.mean
			
			metricPoints[4].mean = newValue.bunchWidth.a.mean
			metricPoints[5].mean = newValue.bunchWidth.b.mean
			metricPoints[6].mean = newValue.bunchWidth.c.mean
			
			metricPoints[7].mean = newValue.interval.a.mean
			metricPoints[8].mean = newValue.interval.b.mean
			
			metricPoints[9].mean = newValue.heightInRise.mean
		}
	}
	
	var currentMeasured:Float {
		willSet {
			label.text = String("\(round(1000*newValue))")
		}
	}
	
	var controlPoint:InertialFloat3
//	var pC:InertialFloat3
	
	var label: UILabel = UILabel()
	
	var deltaX:Int32 = 0
	var deltaY:Int32 = 0
    
	var calcIsNotFreezed = false
	
    private let orientation = UIInterfaceOrientation.landscapeRight
    // Camera's threshold values for detecting when the camera moves so that we can accumulate the points
    private let cameraRotationThreshold = cos(2 * .degreesToRadian)
	private let cameraTranslationThreshold: Float = 0.001*0.001   // (meter-squared)
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
    
    internal lazy var viewArea:MetalBuffer<CameraView> = {
        let viewCorners = [
            CameraView(viewVertices: [-1,1], viewTexCoords: [0,0]),
            CameraView(viewVertices: [-1,-1], viewTexCoords: [0,1]),
            CameraView(viewVertices: [1,1], viewTexCoords: [1,0]),
            CameraView(viewVertices: [1,-1], viewTexCoords: [1,1]),
        ]
        return .init(device: device, array:viewCorners, index: kViewCorner.rawValue)
    }()
    
//    private lazy var unprojectPipelineState = makeUnprojectionPipelineState()!
    private lazy var curveUnprojectPipelineState = makeCurvedUnprojectPipelineState()!
    private lazy var cartesianUnprojectPipelineState = makeCartesianUnprojectPipelineState()!
    private lazy var singleFrameUnprojectPipelineState = makeSingleFrameUnprojectPipelineState()!
    
    internal lazy var cartesianGridPipelineState = makeCartesianGridPipelineState()!
    internal lazy var curvedGridPipelineState = makeCurvedGridPipelineState()!
    internal lazy var singleFramePipelineState = makeSingleFramePipelineState()!
	
	internal lazy var metricPipelineState = makeMetricsFootPipelineState()!
    
    internal lazy var heelMarkerAreaPipelineState = makeHeelMarkerAreaPipelineState()!
	internal lazy var cameraImageState = makeCameraImageState()!
    
    // texture cache for captured image
    private lazy var textureCache = makeTextureCache()
    private var depthTexture: CVMetalTexture?
    private var confidenceTexture: CVMetalTexture?
    internal var capturedImageTextureY: CVMetalTexture?
    internal var capturedImageTextureCbCr: CVMetalTexture?
    
    // Multi-buffer rendering pipeline
    private let inFlightSemaphore: DispatchSemaphore
    internal var currentBufferIndex = 0
    
    
    lazy var segmentationState: MTLComputePipelineState = makeSegmentationState()!
	lazy var reductionBorderState: MTLComputePipelineState = makeReductBorderState()!
	lazy var equalFramePerNodeState: MTLComputePipelineState = makeEqualFamePerMeshNode()!
//	var floorHeight: Float = -10
	var floorCyclicBuffer: CyclicBuffer = CyclicBuffer(count: 10)
    
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
    

    
    // Point Cloud buffer
    internal lazy var pointCloudUniforms: CoordData = {
        var uniforms = CoordData()
        uniforms.cameraResolution = cameraResolution
		uniforms.floorHeight = -10
        return uniforms
    }()
	
	private lazy var cameraViewsPositions:[ViewSector] = {
		let ch:Float = 0.5;		// вертикальная позиция камеры (задаётся произвольно, т.к. пока проверка не использует данный параметр)
		let hh = Float(BOX_HALF_HEIGHT)
		let hw = Float(BOX_HALF_WIDTH)
		var arr = [ViewSector]()
		arr.append(ViewSector(number: 0, coord: simd_float3(0, -hw, ch)))
		arr.append(ViewSector(number: 1, coord: simd_float3(0, hw, ch)))
		return arr
	}()
	
	var currentViewSector:ViewSector?
	
	func findCamZone() -> ViewSector? {
		let deltaSqured:Float = 0.02*0.02;
		for camView in cameraViewsPositions {
			let dr = camPosition - camView.coord;
			let rho = Float(dr.y)
			if (rho*rho < deltaSqured) {
				return camView
			}
		}
		return nil
	}
	
//    internal var pointCloudUniformsBuffers = [MetalBuffer<CoordData>]()
    
    // Camera data
    private var sampleFrame: ARFrame { session.currentFrame! }
    private lazy var cameraResolution = Float2(Float(sampleFrame.camera.imageResolution.width), Float(sampleFrame.camera.imageResolution.height))
    
    internal lazy var viewToCamera:matrix_float3x3 = {
        var mat = matrix_float3x3()
        mat.copy(from: sampleFrame.displayTransform(for: orientation, viewportSize: viewportSize).inverted())
        return mat
    }()
    private lazy var lastCameraTransform = sampleFrame.camera.transform
    
    
    var cartesianGridBuffer: MetalBuffer<MyMeshData>!
	lazy var indecesBuffer: MetalBuffer<UInt32> = initializeGridIndeces()
    
	var curveGridBuffer: (borderPoints:MetalBuffer<BorderPoints>,buffer:MetalBuffer<MyMeshData>)!
	lazy var metricPoints:MetalBuffer<BorderPoints> = {	// пока так...
		// 1 coord center
		// 2 camera
		// 3 toe
		// 4 heel
		// 5 left bunch
		// 6 right bunch
		// 7 toe for bunch
		// 8,9 interval
		// 10 height in rise
		let arr = Array(repeating: BorderPoints(), count: 10)
		return .init(device: device, array: arr, index: kBorderBuffer.rawValue)
	}()
	
    var gistrosBuffer:MTLBuffer!
    func initializeGistrosBuffer(nodeCount:Int) {
        gistrosBuffer = device.makeBuffer(length: MemoryLayout<Gistro>.stride*nodeCount)
    }
    
    
    var frameAccumulated: Int32 = 0;
    
    var currentState:RendererState {
        willSet {
            switch newValue {
            case .findFloorPlane:
                frameAccumulated = 0
				pointCloudUniforms.floorHeight = -10
                initializeCartesianGridNodes()
			case .scanning, .measuring:
                initializeCurveGridNodes()
				metricMode = .lengthToe
			}
        }
    }
	
	func generateBorderBuffer() -> MetalBuffer<BorderPoints> {
		let arr = Array(repeating: BorderPoints(), count: Int(PHI_GRID_NODE_COUNT))
		return .init(device: device, array: arr, index: kBorderBuffer.rawValue)
	}
    
    init(session: ARSession, metalDevice device: MTLDevice, renderDestination: RenderDestinationProvider) {
        self.session = session
        self.device = device
        self.renderDestination = renderDestination
        
        library = device.makeDefaultLibrary()!
        commandQueue = device.makeCommandQueue()!
        
		footMetric = FootMetricProps( length: (a:InertialFloat3(), b:InertialFloat3()),
									  bunchWidth: (a:InertialFloat3(), b:InertialFloat3(), c:InertialFloat3()),
									  interval: (a:InertialFloat3(), b:InertialFloat3()),
									  heightInRise: InertialFloat3(),
									  basis: (el: Float3(1,0,0), en: Float3(0,1,0))
		)
		
		currentMeasured = 0
		controlPoint = InertialFloat3()
		
        inFlightSemaphore = DispatchSemaphore(value: maxInFlightBuffers)
        currentState = .findFloorPlane
        initializeCartesianGridNodes()
        initializeGistrosBuffer(nodeCount: gridCurveNodeCount)
		
		
		
		label.text = "Снимаем носок"
    }
    
    func initializeCartesianGridNodes() {
        let initVal = initMyMeshData(-2)
        let gridInitial = Array(repeating: initVal, count: gridCartesianNodeCount)
        cartesianGridBuffer = .init(device: device, array:gridInitial, index: kMyMesh.rawValue)
    }
    
    func initializeCurveGridNodes() {
        let initVal = initMyMeshData(0)
        let gridInitial = Array(repeating: initVal, count: gridCurveNodeCount)

		curveGridBuffer = ( borderPoints:generateBorderBuffer(),
							buffer:.init(device: device, array:gridInitial, index: kMyMesh.rawValue))
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
    
	private func shouldAccumulate(frame: ARFrame) -> Bool {
		
		if currentState == .findFloorPlane {
			return true
		}
		
		updateCenterAndcamProjection()
		if (currentState == .scanning) {
			
			currentViewSector = findCamZone()
			if currentViewSector == nil {
				return false
			}
		} else {
			currentViewSector = ViewSector(number: -1, coord: .zero)
		}
		
		
		let cameraTransform = frame.camera.transform
		let delta =
//			dot(cameraTransform.columns.2, lastCameraTransform.columns.2) <= cameraRotationThreshold
//			||
			distance_squared(cameraTransform.columns.3, lastCameraTransform.columns.3) < cameraTranslationThreshold
		  
		lastCameraTransform = cameraTransform
		return delta
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
				sum += Double(cartesianGridBuffer[i].mean)
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
        
		if currentState == .findFloorPlane {
			let nc:Int32 = 10
			if ( frameAccumulated%nc == 0 && frameAccumulated != 0 && pointCloudUniforms.floorHeight == -10 ) {
				let fv = Float(cpuCalcFloor())
				floorCyclicBuffer.update(fv)
				if ( floorCyclicBuffer.curLen < 10 || floorCyclicBuffer.deviation > 0.003 ) {
					
					print("\(frameAccumulated/nc) floor \(pointCloudUniforms.floorHeight) fb \(floorCyclicBuffer.deviation)")
				} else {
					pointCloudUniforms.floorHeight = fv
					print("\(frameAccumulated/nc) floor done!!!)")
				}
				
			}
		}
		
//        currentBufferIndex = (currentBufferIndex + 1) % maxInFlightBuffers
//        pointCloudUniformsBuffers[currentBufferIndex][0] = pointCloudUniforms
        

                      
        if canUpdateDepthTextures(frame: currentFrame) {
			calcIsNotFreezed = shouldAccumulate(frame: currentFrame)
			if calcIsNotFreezed {
				accumulatePoints(frame: currentFrame, commandBuffer: commandBuffer, renderEncoder: renderEncoder)
			}
        }
		renderEncoder.setDepthStencilState(relaxedStencilState)
		updateCapturedImageTextures(frame: currentFrame)
		drawCameraStream(renderEncoder)
		switch currentState {
        case .findFloorPlane:
            drawHeelMarker(renderEncoder)
        case .scanning:
            renderEncoder.setDepthStencilState(depthStencilState)
			drawMesh(renderEncoder)
			renderEncoder.setDepthStencilState(relaxedStencilState)
			drawFootMetrics(renderEncoder)
		case .measuring:
            renderEncoder.setDepthStencilState(relaxedStencilState)
			drawMesh(renderEncoder)
			drawFootMetrics(renderEncoder)
        }
    
        renderEncoder.endEncoding()
        commandBuffer.present(renderDestination.currentDrawable!)
        commandBuffer.commit()
    }
    

	
	fileprivate func updateMetric() {
		
		var border = curveGridBuffer.borderPoints	// пока так... заглушка на первый попавшийся буфер
		if currentState == .measuring {
			if metricMode == .lengthToe || metricMode == .lengthHeel {
				pickLengthPoint(&border)
			} else if metricMode == .bunchWidthInner || metricMode == .bunchWidthOuter {
				pickWidthPoint(&border)
			} else {
				pickHeightInRise(&border)
			}
		}
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
		if currentState == .findFloorPlane {
			renderEncoder.setRenderPipelineState(cartesianUnprojectPipelineState)
			renderEncoder.setVertexBuffer(cartesianGridBuffer)
	//		renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
			renderEncoder.setVertexBytes(&pointCloudUniforms, length: MemoryLayout<CoordData>.stride, index: Int(kPointCloudUniforms.rawValue))
			renderEncoder.setVertexBuffer(gridPointsBuffer)

			renderEncoder.setVertexTexture(CVMetalTextureGetTexture(depthTexture!), index: Int(kTextureDepth.rawValue))
			renderEncoder.setVertexTexture(CVMetalTextureGetTexture(confidenceTexture!), index: Int(kTextureConfidence.rawValue))
			renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: gridPointsBuffer.count)

			
		} else {
			renderEncoder.setRenderPipelineState(curveUnprojectPipelineState)

			renderEncoder.setVertexBuffer(curveGridBuffer.buffer)
			
			renderEncoder.setVertexBytes(&pointCloudUniforms, length: MemoryLayout<CoordData>.stride, index: Int(kPointCloudUniforms.rawValue))
			
			renderEncoder.setVertexBytes(&currentViewSector, length: MemoryLayout<ViewSector>.stride, index: Int(kViewSector.rawValue))
			
			
			renderEncoder.setVertexBuffer(gridPointsBuffer)
			renderEncoder.setVertexTexture(CVMetalTextureGetTexture(depthTexture!), index: Int(kTextureDepth.rawValue))
			renderEncoder.setVertexTexture(CVMetalTextureGetTexture(confidenceTexture!), index: Int(kTextureConfidence.rawValue))
			renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: gridPointsBuffer.count)
			
			
			if frameAccumulated%30 == 0 {
				updateAllNodes()
			}
			
			startSegmentation()
			reductBorderPoints()
//			updateMetric()
		}
		frameAccumulated += 1
    }
}

private extension Renderer {
	
	/// Makes sample points on camera image, also precompute the anchor point for animation
	func makeGridPoints() -> [Float2] {
		let numGridPoints = 3000_000;
		let gridArea = cameraResolution.x * cameraResolution.y
		let spacing = sqrt(gridArea / Float(numGridPoints))
		deltaX = Int32(round(cameraResolution.x / spacing))
		deltaY = Int32(round(cameraResolution.y / spacing))
		
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
