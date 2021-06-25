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
		
		
		// TODO: на вход подавать xCoord в базисе ноги!
		func findInterval(_ xCoord:Float, _ range:(iStart:Int, iEnd:Int)) -> Int? {
			for i in range.iStart..<range.iEnd {
				let p0 = buffer[i].mean
				let p1 = buffer[i+1].mean
				if ((p0.x-xCoord)*(p1.x-xCoord) < 0) {
					return i
				}
			}
			return nil
		}
		// END TODO
		
		// find toe point
		let interval = (a: anglePos(alpha: Float(11)/Float(12)*Float.pi),
						   b: anglePos(alpha: Float(13)/Float(12)*Float.pi))
		let pickedPointIndex = findIndexOfFarthestDistance(buffer: buffer, interval: interval, isToe: true)
//		markPoint(&buffer, indeces: interval)
		footMetric.bunchWidth.c.mean = buffer[pickedPointIndex].mean	// the toe point
		
		let percent:(from:Float,to:Float) = (metricMode == .bunchWidthOuter) ? (from: 0.85,to:0.55): (from: 0.9,to:0.6)
		
		// TODO: пересчитать xToe xHeel в базисе ноги
		let footLen = length(footMetric.length.a.mean - footMetric.length.b.mean)
		let xToe = footMetric.bunchWidth.c.mean.x + footLen*(1 - percent.from)
		let xHeel = footMetric.bunchWidth.c.mean.x + footLen*(1 - percent.to)
		// END TODO
		
		// в зависимости от состояния
		let searchInterval:(Int,Int) = (metricMode == .bunchWidthOuter) ? (0, pickedPointIndex)
			: (pickedPointIndex, buffer.count)
		
		let iStart:Int! = findInterval(xToe, searchInterval)
		let iEnd:Int! = findInterval(xHeel, searchInterval)
		
		if (iStart != nil && iEnd != nil) {
			// update interval
			footMetric.interval.a.mean = buffer[iStart].mean
			footMetric.interval.b.mean = buffer[iEnd].mean
			
			// TODO: вычислять maxY в базисе ноги
			var maxY:Float = 0
			var p:Float3!
			for i in min(iStart,iEnd)..<max(iStart,iEnd) {
				if (abs(buffer[i].mean.y) > maxY) {
					maxY = abs(buffer[i].mean.y)
					p = buffer[i].mean
				}
			}
			// END TODO
			
			if p != nil {
				currentMeasuredPoint.mean = p
				
				if metricMode == .bunchWidthOuter {
					footMetric.bunchWidth.a.mean = currentMeasuredPoint.mean
					print("!!!!! bunch width OUTER !!!!")
				} else {
					footMetric.bunchWidth.b.mean = currentMeasuredPoint.mean
					print("!!!!! bunch width INNER !!!!")
				}
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
		// update interval
		footMetric.interval.a.mean = buffer[interval.a].mean
		footMetric.interval.b.mean = buffer[interval.b].mean
	
		let pp = buffer[pickedPointIndex].mean
		
		if metricMode == .lengthToe {
			footMetric.length.a.mean = pp
		} else if metricMode == .lengthHeel {
			footMetric.length.b.mean = pp
		}
		currentMeasuredPoint.mean = pp
	}
	
	
	func updateCenterAndcamProjection() {
		// центр ЛКС
		borderBuffer[Int(PHI_GRID_NODE_COUNT)].mean = simd_float3(repeating:0)
		
		// прокекция камеры
		let mat = pointCloudUniforms.localToWorld;
		let camPos = mat*simd_float4(0, 0, 0, 1);
		let toLocalCS = float4x4( simd_float4( 1, 0, 0, 0),
								  simd_float4( 0, 0, 1, 0),
								  simd_float4( 0, 1, 0, 0),
								  simd_float4( 0, 0, -pointCloudUniforms.floorHeight, 1)
		)
		let camPosLoc = toLocalCS*camPos
		borderBuffer[Int(PHI_GRID_NODE_COUNT+1)].mean = simd_float3(camPosLoc.x, camPosLoc.y, camPosLoc.z)
	}
}
