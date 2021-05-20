import MetalKit

extension Renderer {

    public func calcNormals(bufferIn: MetalBuffer<MyMeshData>) {
                
		guard let commandBuffer = commandQueue.makeCommandBuffer(),
			  let commandEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
		
        commandEncoder.setComputePipelineState(computeNormalsState)
        
        commandEncoder.setBuffer(bufferIn)
        
		let nTotal = MTLSize(width: bufferIn.count, height: 1, depth: 1)
        let w = MTLSize(width: computeNormalsState.maxTotalThreadsPerThreadgroup, height: 1, depth: 1)
        commandEncoder.dispatchThreads(nTotal, threadsPerThreadgroup: w)
        
        commandEncoder.endEncoding()
        commandBuffer.commit()
        
        commandBuffer.waitUntilCompleted()

    }
    
}
