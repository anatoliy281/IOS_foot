import MetalKit


func gpuWay(inBuffer: MTLBuffer, _ pipelineState: MTLComputePipelineState) -> Float {
    var res = Float()
    
    var buffer = inBuffer
    let bufferLength = buffer.length/MemoryLayout<Float>.stride
    var halfLen = bufferLength / 2
    
    
    for _ in 0..<Int( log2f(Float(bufferLength)) ) {
        // Create a buffer to be sent to the command queue
        let commandBuffer = commandQueue.makeCommandBuffer()!

        // Create an encoder to set vaulues on the compute function
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        commandEncoder.setComputePipelineState(pipelineState)

        let resBuffer = device.makeBuffer(length: buffer.length/2)!
        
        // Set the parameters of our gpu function
        commandEncoder.setBuffer(buffer, offset: 0, index: 0)
        commandEncoder.setBuffer(buffer, offset: MemoryLayout<Float>.stride * halfLen, index: 1)
        commandEncoder.setBuffer(resBuffer, offset: 0, index: 2)
        
        // Figure out how many threads we need to use for our operation
        let threadsPerGrid = MTLSize(width: halfLen, height: 1, depth: 1)
        let threadsPerThreadgroup = MTLSize(width: pipelineState.maxTotalThreadsPerThreadgroup,
                                            height: 1,
                                            depth: 1)
        commandEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)


        commandEncoder.endEncoding()  // Tell the encoder that it is done encoding.  Now we can send this off to the gpu.
        commandBuffer.commit() // Push this command to the command queue for processing

        commandBuffer.waitUntilCompleted() // Wait until the gpu function completes before working with any of the data
        buffer = resBuffer
        
        halfLen /= 2
        
        if halfLen == 0 {
            res = Float(buffer.contents().load(as: Float.self))
        }
    }
    
    return res
}
