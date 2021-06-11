import MetalKit

extension Renderer {

	public func calcFootMetrics(bufferIn: MetalBuffer<MyMeshData>,
								heel: MetalBuffer<GridPoint>,
								toe: MetalBuffer<GridPoint>,
								metricIndeces: inout MetricIndeces) {
                
		guard let commandBuffer = commandQueue.makeCommandBuffer(),
			  let commandEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
		
        commandEncoder.setComputePipelineState(computeFootMetricState)
        
        commandEncoder.setBuffer(bufferIn)
		commandEncoder.setBuffer(heel)
		commandEncoder.setBuffer(toe)
		commandEncoder.setBytes(&metricIndeces, length: MemoryLayout<MetricIndeces>.stride, index: Int(kMetricIndeces.rawValue))
        
		let nTotal = MTLSize(width: bufferIn.count, height: 1, depth: 1)
        let w = MTLSize(width: computeFootMetricState.maxTotalThreadsPerThreadgroup, height: 1, depth: 1)
        commandEncoder.dispatchThreads(nTotal, threadsPerThreadgroup: w)
        
        commandEncoder.endEncoding()
        commandBuffer.commit()
        
        commandBuffer.waitUntilCompleted()

    }
	

	func fromGiperbolicToCartesian(value:Float, index:Int32) -> Float3 {
		
		let du = Double(LENGTH*LENGTH) / Double(U_GRID_NODE_COUNT)
		let dPhi = (2*Double.pi) / Double(PHI_GRID_NODE_COUNT)
		
		let u = Double( index/PHI_GRID_NODE_COUNT - U0_GRID_NODE_COUNT )*du
		let v = Double(value);
		
		let uv_sqrt = sqrt(v*v + u*u);
		let rho = sqrt(0.5*(u + uv_sqrt));
		let h = sqrt(rho*rho - u);
		
		let phi = Double(Int32(index)%PHI_GRID_NODE_COUNT)*dPhi;

		return Float3(Float(rho)*Float(cos(phi)), Float(rho*sin(phi)), Float(h));
	}
	
	
	func inFrameBoxOfFoot(pos:Float3) -> Bool {
		let checkHeight = pos.z < Float(HEIGHT_OVER_FLOOR)
		let checkWidth = abs(pos.y) < Float(BOX_HALF_WIDTH)
		let checkLength = (pos.x < 0) ? -pos.x < Float(BOX_FRONT_LENGTH) :
										pos.x < Float(BOX_BACK_LENGTH)
		return checkWidth && checkHeight && checkLength
	}
	
	public func calcDistance(heel: inout MetalBuffer<GridPoint>, toe: inout MetalBuffer<GridPoint>) -> (Float, Float) {
		
		func bufferMean(buffer: inout MetalBuffer<GridPoint>, ik:Int) -> Float3 {
			var totalRho:Float3 = .init(0, 0, 0)
			var cnt:Int = 0
			for i in (0..<buffer.count-ik).reversed() {
				let r0 = fromGiperbolicToCartesian(value: buffer[i].rho, index: buffer[i].index)
				let rk = fromGiperbolicToCartesian(value: buffer[i+ik].rho, index: buffer[i+ik].index)
				
				if (!inFrameBoxOfFoot(pos: r0) || !inFrameBoxOfFoot(pos: rk)) {
					continue
				}
				
				let dr = rk - r0
				if ( length_squared(dr) / (dr.z*dr.z) < 2 ) {	// производная больше 45 градусов
					totalRho += r0
					buffer[i].checked = 1;
					cnt += 1
				}
			}
			return totalRho / Float(cnt)
		}
		
		func vMeanInRegion(buffer: MetalBuffer<GridPoint>, _ v0:Float, _ v1:Float) -> Float3 {
			var total:Float3 = .init(0,0,0)
			var cnt:Int = 0
			for i in 0..<buffer.count {
				
				let r0 = fromGiperbolicToCartesian(value: buffer[i].rho, index: buffer[i].index)
				if (!inFrameBoxOfFoot(pos: r0)) {
					continue
				}
				
				let v = buffer[i].rho
				if (v >= v0 && v <= v1) {
					total += fromGiperbolicToCartesian(value: v, index: buffer[i].index)
					cnt += 1
				}
			}
			return total / Float(cnt)
		}
		
		func hMeanInRegion(buffer: MetalBuffer<GridPoint>, _ h:Float, _ dh:Float) -> Float3 {
			var total:Float3 = .init(0,0,0)
			var cnt:Int = 0
			for i in 0..<buffer.count {
				let v = buffer[i].rho
				let r0 = fromGiperbolicToCartesian(value: v, index: buffer[i].index)
				if (!inFrameBoxOfFoot(pos: r0)) {
					continue
				}
				
				if ( r0.z >= h && r0.z <= h+dh ) {
					total += fromGiperbolicToCartesian(value: v, index: buffer[i].index)
					cnt += 1
				}
			}
			return total / Float(cnt)
		}

		let heelRho = bufferMean(buffer: &heel, ik: 2)
		let toeRho = bufferMean(buffer: &toe, ik: 10)
		let distance = heelRho - toeRho
		
//		let v0:Float = 0.002
//		let v1:Float = 0.004
//		let dist2 = vMeanInRegion(buffer: heel, v0, v1) - vMeanInRegion(buffer: toe, v0, v1)
		let h:Float = 0.004
		let dh:Float = 0.004
		let dist3 = hMeanInRegion(buffer: heel, h, dh) - hMeanInRegion(buffer: toe, h, dh)
		
		return ( length(distance), length(dist3) )
	}
    
}
