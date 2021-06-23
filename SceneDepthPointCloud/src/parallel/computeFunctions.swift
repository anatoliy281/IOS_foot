import MetalKit

extension Renderer {

	public func startSegmentation(grid: MetalBuffer<MyMeshData>, pointsBuffer: MetalBuffer<BorderPoints>) {
                
		guard let commandBuffer = commandQueue.makeCommandBuffer(),
			  let commandEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
		
        commandEncoder.setComputePipelineState(segmentationState)
        
        commandEncoder.setBuffer(grid)
		commandEncoder.setBuffer(pointsBuffer)
        
		let nTotal = MTLSize(width: grid.count, height: 1, depth: 1)
        let w = MTLSize(width: segmentationState.maxTotalThreadsPerThreadgroup, height: 1, depth: 1)
        commandEncoder.dispatchThreads(nTotal, threadsPerThreadgroup: w)
        
        commandEncoder.endEncoding()
        commandBuffer.commit()
        
        commandBuffer.waitUntilCompleted()

    }
	
	public func reductBorderPoints(border: MetalBuffer<BorderPoints>) {
		guard let commandBuffer = commandQueue.makeCommandBuffer(),
			  let commandEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
		
		commandEncoder.setComputePipelineState(reductionBorderState)
		commandEncoder.setBuffer(border)
		
		let nTotal = MTLSize(width: border.count, height: 1, depth: 1)
		let w = MTLSize(width: reductionBorderState.maxTotalThreadsPerThreadgroup, height: 1, depth: 1)
		commandEncoder.dispatchThreads(nTotal, threadsPerThreadgroup: w)
		
		commandEncoder.endEncoding()
		commandBuffer.commit()
		
		commandBuffer.waitUntilCompleted()
	}
	

	
	
	func inFrameBoxOfFoot(pos:Float3) -> Bool {
		let checkHeight = pos.z < Float(HEIGHT_OVER_FLOOR)
		let checkWidth = abs(pos.y) < Float(BOX_HALF_WIDTH)
		let checkLength = (pos.x < 0) ? -pos.x < Float(BOX_FRONT_LENGTH) :
										pos.x < Float(BOX_BACK_LENGTH)
		return checkWidth && checkHeight && checkLength
	}
	
//	// depricated
//	func peekPoint(_ buffer: MetalBuffer<BorderPoints>, alpha: Float) -> Float3 {
//		let dAlpha = 2*Float.pi / Float(buffer.count)
//		return buffer[Int(alpha/dAlpha)].mean
//	}
	
//	// depricated
//	func markPoint(_ buffer: inout MetalBuffer<BorderPoints>, alpha: Float) {
//		let dAlpha = 2*Float.pi / Float(buffer.count)
//		buffer[Int(alpha/dAlpha)].typePoint = metric;
//	}
	
	func markPoint(_ buffer: inout MetalBuffer<BorderPoints>, indeces: (a:Int, b:Int)?, i:Int) {
		
		if (indeces != nil) {
			buffer[indeces!.a].typePoint = leftSide
			buffer[indeces!.b].typePoint = rightSide
		}
		buffer[i].typePoint = metric
	}
	
	
	func convertToMm(cm length:Float) -> Float {
		return round(1000*length)
	}
	
	func anglePos(alpha: Float) -> Int {
		let dAlpha = 2*Float.pi / Float(PHI_GRID_NODE_COUNT)
		return Int(alpha/dAlpha)
	}
	
	
	// percent from (toe) to (heel) -> (out, inner)
	// isOuter marks outer point
	func pickWidthPoint(_ buffer: inout MetalBuffer<BorderPoints>) {
		
		func findInterval(xCoord:Float, _ buffer: inout MetalBuffer<BorderPoints>) -> Int? {
			
			if metricMode == .bunchWidthInner {
				for i in (1..<buffer.count).reversed() {
					let p0 = buffer[i].mean
					let p1 = buffer[i-1].mean
					if ((p0.x-xCoord)*(p1.x-xCoord) < 0) {
						return i
					}
				}
				return nil
			} else {
				for i in 0..<buffer.count-1 {
					let p0 = buffer[i].mean
					let p1 = buffer[i+1].mean
					if ((p0.x-xCoord)*(p1.x-xCoord) < 0) {
						return i
					}
				}
				return nil
			}
			
			
		}
		
		// find toe point
		let interval = (a: anglePos(alpha: Float(11)/Float(12)*Float.pi),
						   b: anglePos(alpha: Float(13)/Float(12)*Float.pi))
		let pickedPointIndex = findIndexOfFarthestDistance(buffer: buffer, interval: interval, isToe: true)
		markPoint(&buffer, indeces: nil, i: pickedPointIndex)
		let pp = buffer[pickedPointIndex].mean	// the toe point
		
		// find x interval
		let percent:(from:Float,to:Float) = (metricMode == .bunchWidthOuter) ? (from: 0.75,to:0.65): (from: 0.7,to:0.6)
		
		let footLen = length(footMetric.length.a - footMetric.length.b)
		let xToe = pp.x + footLen*(1 - percent.from)
		let xHeel = pp.x + footLen*(1 - percent.to)
		let iStart:Int! = findInterval(xCoord: xToe, &buffer)
		let iEnd:Int! = findInterval(xCoord: xHeel, &buffer)
	
		if (iStart != nil && iEnd != nil) {
			var maxY:Float = 0
			var p:Float3!
			var iFind:Int!
			for i in min(iStart,iEnd)..<max(iStart,iEnd) {
				if (abs(buffer[i].mean.y) > maxY) {
					maxY = abs(buffer[i].mean.y)
					p = buffer[i].mean
					iFind = i
				}
			}
			
			if iFind == nil {
				return
			}
			
			markPoint(&borderBuffer, indeces: (a:iStart,b:iEnd), i: iFind)
			
			if metricMode == .bunchWidthInner {
				footMetric.bunchWidth.a = p
			} else {
				footMetric.bunchWidth.b = p
			}
			
		}
	}
	
	public func pickLengthPoint(_ buffer: inout MetalBuffer<BorderPoints>) {
		
		var pickedPointIndex:Int
		let interval:(a:Int,b:Int)
		if metricMode == .lengthToe {
			interval = (a: anglePos(alpha: Float(11)/Float(12)*Float.pi),
							   b: anglePos(alpha: Float(13)/Float(12)*Float.pi))
			pickedPointIndex = findIndexOfFarthestDistance(buffer: buffer, interval: interval, isToe: true)
			
		} else {
			interval = (a: anglePos(alpha: 0.5*Float.pi),
								b: anglePos(alpha: 1.5*Float.pi))
			pickedPointIndex = findIndexOfFarthestDistance(buffer: buffer, interval: interval, isToe: false)

		}
		
		markPoint(&buffer, indeces: interval, i: pickedPointIndex)
	
		let pp = buffer[pickedPointIndex].mean
		
		if metricMode == .lengthToe {
			footMetric.length.a = pp
			label.text = String("\(round(1000*pp.x))")
//			print(1000*length(pp))
			print("toe")
		} else if metricMode == .lengthHeel {
			footMetric.length.b = pp
			label.text = String("\(round(1000*pp.x))")
			print("heel")
		}
	
//		let res = convertToMm(cm: length(float2(distance.x, distance.y)))
//		if res.isFinite {
//
//			return res
//		} else {
//			return nil
//		}
	}
	
//	func findBunchPoint(_ buffer: inout MetalBuffer<BorderPoints>, searchedX x:Float, isOuter:Bool) -> Float3? {
//		var iStart = buffer.count / 2
//		let dI = (isOuter) ? -1 : 1
//		while iStart%buffer.count != 0 {
//			let p0 = buffer[iStart].mean
//			let p1 = buffer[iStart + dI].mean
//			if ( p0.x < x && x < p1.x ) {
//				buffer[iStart].typePoint = metric
//				return 0.5*(p0 + p1)
//			}
//			iStart += dI
//		}
//		return nil
//	}
    
//	public func calcBunchWidth(_ buffer: inout MetalBuffer<BorderPoints>) -> Int? {
//		let length = 0 // TODO
//		let l = 0.001*Float(length)
//		let dxOuter = (Float(1 - 0.77)*l, Float(1 - 0.635)*l)
//		let dxInner = (Float(1 - 0.8)*l, Float(1 - 0.635)*l)
//
//		// Приближение, что носок (самая удалённая точка) лежит на оси OX
//		let toePoint = peekPoint(buffer, alpha: Float.pi)
////		markPoint(&buffer, alpha: Float.pi)
//		// Приближение, что пучки лежат посередине интервала
//		let outerDX = 0.5*(dxOuter.0 + dxOuter.1)
//		let innerDX = 0.5*(dxInner.0 + dxInner.1)
//		// искомые координаты пучков в рамках данных приближений
//		let outerX = toePoint.x + outerDX
//		let innerX = toePoint.x + innerDX
//
//		guard let pA = findBunchPoint(&buffer, searchedX: outerX, isOuter: true),
//			  let pB = findBunchPoint(&buffer, searchedX: innerX, isOuter: false) else {
//			return nil
//		}
//
//		return 0 // TODO
////			convertToMm(cm: length(pA - pB))
////		if res.isFinite {
////			return res
////		} else {
////			return nil
////		}
//	}
	
	
	func updateCenterAndcamProjection() {
		// центр ЛКС
		borderBuffer[Int(PHI_GRID_NODE_COUNT)].mean = simd_float3(repeating:0)
		borderBuffer[Int(PHI_GRID_NODE_COUNT)].typePoint = metric
		
		// прокекция камеры
		let mat = pointCloudUniforms.localToWorld;
		let camPos = mat*simd_float4(0, 0, 0, 1);
		let toLocalCS = float4x4( simd_float4( 1, 0, 0, 0),
								  simd_float4( 0, 0, 1, 0),
								  simd_float4( 0, 1, 0, 0),
								  simd_float4( 0, 0, -pointCloudUniforms.floorHeight, 1)
		)
		var camPosLoc = toLocalCS*camPos
//		camPosLoc.z = 0
		
		borderBuffer[Int(PHI_GRID_NODE_COUNT+1)].mean = simd_float3(camPosLoc.x, camPosLoc.y, camPosLoc.z)
		borderBuffer[Int(PHI_GRID_NODE_COUNT+1)].typePoint = camera
	}
}
