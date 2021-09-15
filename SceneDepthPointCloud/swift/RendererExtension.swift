import Foundation

class RendererExtension {
	
	typealias PointBuffer = MetalBuffer<ParticleUniforms>
	typealias IndexBuffer = MetalBuffer<UInt32>

	let device:MTLDevice
	let resources:Resourses
	let caller:CPPCaller
	
	init(renderDevice:MTLDevice, renderCPPCaller:CPPCaller) {
		device = renderDevice
		caller = renderCPPCaller
		resources = .init()
	}
	
	func showIndexBuffer(buffer:IndexBuffer, hideEmpty:Bool = true) {
		print("buffer begin")
		for i in stride(from: 0, to: buffer.count-2, by: 3) {
			let allEmpty = buffer[i] == 0 && buffer[i+1] == 0 && buffer[i+2] == 0
			if (hideEmpty && allEmpty) {
				continue
			} else {
				print("{\(i)} \(buffer[i]) \(buffer[i+1]) \(buffer[i+2])")
			}
		}
		print("buffer end")
	}
	
	func buildBuffers (points:[ParticleUniforms]) -> (vertecesBuffer: PointBuffer,indecesBuffer: IndexBuffer) {
		let testPointBuf:PointBuffer = .init(device: device, array: points, index: kParticleUniforms.rawValue)
		let trianglesCount = 8
		let vertexInTriangle = 3
		let testIndexBuf:IndexBuffer = .init(device: device, count: trianglesCount*vertexInTriangle, index: 0)
		caller.triangulate(testPointBuf.buffer, testIndexBuf.buffer)

		return (testPointBuf, testIndexBuf)
	}
	
	func renderBuffers(verteces:PointBuffer,
					   indeces:IndexBuffer,
					   encoder:MTLRenderCommandEncoder,
					   state:MTLRenderPipelineState,
					   uniforms: MetalBuffer<PointCloudUniforms>
					   ) {
		let depthStateDescriptor = MTLDepthStencilDescriptor()
		depthStateDescriptor.depthCompareFunction = .lessEqual
		depthStateDescriptor.isDepthWriteEnabled = true
		let depthStencilState = device.makeDepthStencilState(descriptor: depthStateDescriptor)!
		encoder.setDepthStencilState(depthStencilState)
		encoder.setRenderPipelineState(state)
		encoder.setVertexBuffer(uniforms)
		encoder.setVertexBuffer(verteces)
		
//        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: currentPointCount)
		encoder.drawIndexedPrimitives(type: .lineStrip,
													indexCount: indeces.count,
													indexType: .uint32,
													indexBuffer: indeces.buffer,
													indexBufferOffset: 0)
	}
}
