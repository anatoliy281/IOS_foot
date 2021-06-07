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
	

	

	
	public func calcDistance(heel: inout MetalBuffer<GridPoint>, toe: inout MetalBuffer<GridPoint>) -> Float {
		
		let dRhoMax:Float = 0.001;
		
		func bufferMean(buffer: inout MetalBuffer<GridPoint>) -> Float {
			var totalRho:Float = 0;
			var cnt:Int = 0
			for i in 0..<buffer.count-1 {
				if ( abs(buffer[i].rho - buffer[i+1].rho) < dRhoMax ) {
					totalRho += buffer[i].rho
					buffer[i].checked = 1;
					cnt += 1
				} else if (cnt != 0) {
					break;
				}
			}
			return totalRho / Float(cnt)
		}

		let heelRho = bufferMean(buffer: &heel)
		let toeRho = bufferMean(buffer: &toe)
		
		return toeRho + heelRho
	}
    
}
