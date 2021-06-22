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
	
	// depricated
	func peekPoint(_ buffer: MetalBuffer<BorderPoints>, alpha: Float) -> Float3 {
		let dAlpha = 2*Float.pi / Float(buffer.count)
		return buffer[Int(alpha/dAlpha)].mean
	}
	
	// depricated
	func markPoint(_ buffer: inout MetalBuffer<BorderPoints>, alpha: Float) {
		let dAlpha = 2*Float.pi / Float(buffer.count)
		buffer[Int(alpha/dAlpha)].typePoint = metric;
	}
	
	func markPoint(_ buffer: inout MetalBuffer<BorderPoints>, indeces: (a:Int, b:Int), i:Int) {
		buffer[indeces.a].typePoint = leftSide
		buffer[i].typePoint = metric
		buffer[indeces.b].typePoint = rightSide
	}
	
	func convertToMm(cm length:Float) -> Float {
		return round(1000*length)
	}
	
	func anglePos(alpha: Float) -> Int {
		let dAlpha = 2*Float.pi / Float(PHI_GRID_NODE_COUNT)
		return Int(alpha/dAlpha)
	}
	
	public func pickLengthPoint(_ buffer: inout MetalBuffer<BorderPoints>) {
		
		var pickedPointIndex:Int
		let interval:(a:Int,b:Int)
		if metricMode == .lengthToe {
			interval = (a: anglePos(alpha: Float(11)/Float(12)*Float.pi),
							   b: anglePos(alpha: Float(13)/Float(12)*Float.pi))
			pickedPointIndex = findIndexOfFarthestDistance(buffer: buffer, interval: interval, isToe: true)
			
		} else { //  metricMode == .lengthHeel
			interval = (a: anglePos(alpha: 0.5*Float.pi),
								b: anglePos(alpha: 1.5*Float.pi))
			pickedPointIndex = findIndexOfFarthestDistance(buffer: buffer, interval: interval, isToe: false)

		}
		
		markPoint(&buffer, indeces: interval, i: pickedPointIndex)
	
		let pp = buffer[pickedPointIndex].mean
		
		if metricMode == .lengthToe {
			footMetric.length.a = pp
			print(1000*length(pp))
		} else if metricMode == .lengthHeel {
			footMetric.length.b = pp
			print(1000*length(pp))
		}
	
//		let res = convertToMm(cm: length(float2(distance.x, distance.y)))
//		if res.isFinite {
//
//			return res
//		} else {
//			return nil
//		}
	}
	
	func findBunchPoint(_ buffer: inout MetalBuffer<BorderPoints>, searchedX x:Float, isOuter:Bool) -> Float3? {
		var iStart = buffer.count / 2
		let dI = (isOuter) ? -1 : 1
		while iStart%buffer.count != 0 {
			let p0 = buffer[iStart].mean
			let p1 = buffer[iStart + dI].mean
			if ( p0.x < x && x < p1.x ) {
				buffer[iStart].typePoint = metric
				return 0.5*(p0 + p1)
			}
			iStart += dI
		}
		return nil
	}
    
	public func calcBunchWidth(_ buffer: inout MetalBuffer<BorderPoints>) -> Int? {
		let length = 0 // TODO
		let l = 0.001*Float(length)
		let dxOuter = (Float(1 - 0.77)*l, Float(1 - 0.635)*l)
		let dxInner = (Float(1 - 0.8)*l, Float(1 - 0.635)*l)

		// Приближение, что носок (самая удалённая точка) лежит на оси OX
		let toePoint = peekPoint(buffer, alpha: Float.pi)
//		markPoint(&buffer, alpha: Float.pi)
		// Приближение, что пучки лежат посередине интервала
		let outerDX = 0.5*(dxOuter.0 + dxOuter.1)
		let innerDX = 0.5*(dxInner.0 + dxInner.1)
		// искомые координаты пучков в рамках данных приближений
		let outerX = toePoint.x + outerDX
		let innerX = toePoint.x + innerDX
		
		guard let pA = findBunchPoint(&buffer, searchedX: outerX, isOuter: true),
			  let pB = findBunchPoint(&buffer, searchedX: innerX, isOuter: false) else {
			return nil
		}
		
		return 0 // TODO
//			convertToMm(cm: length(pA - pB))
//		if res.isFinite {
//			return res
//		} else {
//			return nil
//		}
	}
	
}
