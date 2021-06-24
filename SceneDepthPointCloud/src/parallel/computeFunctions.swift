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
	
	func markPoint(_ buffer: inout MetalBuffer<BorderPoints>, indeces: (a:Int, b:Int)) {
		buffer[indeces.a].typePoint = leftSide
		buffer[indeces.b].typePoint = rightSide
		buffer[Int(PHI_GRID_NODE_COUNT + 2)].typePoint = metric
		buffer[Int(PHI_GRID_NODE_COUNT + 3)].typePoint = metric
		buffer[Int(PHI_GRID_NODE_COUNT + 4)].typePoint = metric
		buffer[Int(PHI_GRID_NODE_COUNT + 5)].typePoint = metric
		if (metricMode == .lengthToe) {
			buffer[Int(PHI_GRID_NODE_COUNT + 2)].typePoint = metricNow
		} else if (metricMode == .lengthHeel) {
			buffer[Int(PHI_GRID_NODE_COUNT + 3)].typePoint = metricNow
		} else if (metricMode == .bunchWidthOuter) {
			buffer[Int(PHI_GRID_NODE_COUNT + 2)].typePoint = metricNow	// точка носк становится снова измеряемой в данный момент
			buffer[Int(PHI_GRID_NODE_COUNT + 4)].typePoint = metricNow
		} else if (metricMode == .bunchWidthInner) {
			buffer[Int(PHI_GRID_NODE_COUNT + 2)].typePoint = metricNow // точка носк становится снова измеряемой в данный момент
			buffer[Int(PHI_GRID_NODE_COUNT + 5)].typePoint = metricNow
		}
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
//		markPoint(&buffer, indeces: interval)
		pC.mean = buffer[pickedPointIndex].mean	// the toe point
		
		// find x interval
		let percent:(from:Float,to:Float) = (metricMode == .bunchWidthOuter) ? (from: 0.75,to:0.65): (from: 0.7,to:0.6)
		
		let footLen = length(footMetric.length.a.mean - footMetric.length.b.mean)
		let xToe = pC.mean.x + footLen*(1 - percent.from)
		let xHeel = pC.mean.x + footLen*(1 - percent.to)
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
			
			markPoint(&borderBuffer, indeces: (a:iStart,b:iEnd))
			
			if metricMode == .bunchWidthOuter {
				footMetric.bunchWidth.a.mean = buffer[iFind].mean
			} else {
				footMetric.bunchWidth.b.mean = buffer[iFind].mean
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
		
		markPoint(&buffer, indeces: interval)
	
		let pp = buffer[pickedPointIndex].mean
		
		if metricMode == .lengthToe {
			footMetric.length.a.mean = pp
			pA.mean = pp
			label.text = String("\(round(1000*pA.mean.x))")
//			print(1000*length(pp))
			print("toe")
		} else if metricMode == .lengthHeel {
			footMetric.length.b.mean = pp
			pB.mean = pp
			label.text = String("\(round(1000*pB.mean.x))")
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
	}
}
