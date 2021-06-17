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
	
	func peekPoint(_ buffer: MetalBuffer<BorderPoints>, alpha: Float) -> Float3 {
		let dAlpha = 2*Float.pi / Float(buffer.count)
		return buffer[Int(alpha/dAlpha)].mean
	}
	
	func markPoint(_ buffer: inout MetalBuffer<BorderPoints>, alpha: Float) {
		let dAlpha = 2*Float.pi / Float(buffer.count)
		buffer[Int(alpha/dAlpha)].isMetric = 1;
	}
	
	func convertToMm(cm length:Float) -> Float {
		return round(1000*length)
	}
	
	public func calcLength(_ buffer: inout MetalBuffer<BorderPoints>) -> Float? {
		let heelRho = peekPoint(buffer, alpha: 0)
		let toeRho = peekPoint(buffer, alpha: Float.pi)
		let distance = heelRho - toeRho
	
		let res = convertToMm(cm: length(distance))
		if res.isFinite {
			markPoint(&buffer, alpha: 0)
			markPoint(&buffer, alpha: Float.pi)
			return res
		} else {
			return nil
		}
	}
	
	func findBunchPoint(_ buffer: inout MetalBuffer<BorderPoints>, searchedX x:Float, isOuter:Bool) -> Float3? {
		var iStart = buffer.count / 2
		let dI = (isOuter) ? -1 : 1
		while iStart%buffer.count != 0 {
			let p0 = buffer[iStart].mean
			let p1 = buffer[iStart + dI].mean
			if ( p0.x < x && x < p1.x ) {
				buffer[iStart].isMetric = 1
				return 0.5*(p0 + p1)
			}
			iStart += dI
		}
		return nil
	}
    
	public func calcBunchWidth(_ buffer: inout MetalBuffer<BorderPoints>) -> Float? {
		let l = 0.001*Float(footMetric.length)
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
		
		let res = convertToMm(cm: length(pA - pB))
		if res.isFinite {
			return res
		} else {
			return nil
		}
	}
	
}
