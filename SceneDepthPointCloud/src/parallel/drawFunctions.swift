import MetalKit

extension Renderer {

	func drawCameraStream(_ renderEncoder:MTLRenderCommandEncoder) {
		renderEncoder.setRenderPipelineState(cameraImageState)
		renderEncoder.setVertexBuffer(viewArea)
		renderEncoder.setVertexBytes(&viewToCamera, length: MemoryLayout<CGAffineTransform>.stride, index: Int(kViewToCam.rawValue))
		renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(capturedImageTextureY!), index: Int(kTextureY.rawValue))
		renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(capturedImageTextureCbCr!), index: Int(kTextureCbCr.rawValue))
		renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: viewArea.count)
	}
	
	func drawHeelMarker(_ renderEncoder:MTLRenderCommandEncoder) {
		renderEncoder.setRenderPipelineState(heelMarkerAreaPipelineState)
		renderEncoder.setVertexBuffer(heelAreaMesh.vertexBuffers[0].buffer,
									  offset: 0,
									  index: Int(kHeelArea.rawValue))
		renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
		renderEncoder.setVertexBytes(&floorHeight, length: MemoryLayout<Float>.stride, index: Int(kHeight.rawValue))
		
		guard let submesh = heelAreaMesh.submeshes.first else { return }
		renderEncoder.drawIndexedPrimitives(type: .triangle,
											indexCount: submesh.indexCount,
											indexType: submesh.indexType,
											indexBuffer: submesh.indexBuffer.buffer,
											indexBufferOffset: submesh.indexBuffer.offset)
	}
	
	func drawMesh(gridType:Int, _ renderEncoder:MTLRenderCommandEncoder) {
		var state: MTLRenderPipelineState
		var buffer: MetalBuffer<MyMeshData>
		if gridType == 1 { // Spherical
			state = cylindricalGridPipelineState
			buffer = curveGridBuffer
		} else {
			state = cartesianGridPipelineState
			buffer = cartesianGridBuffer
		}
		renderEncoder.setRenderPipelineState(state)
		renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
		renderEncoder.setVertexBuffer(buffer)
		renderEncoder.setVertexBytes(&floorHeight, length: MemoryLayout<Float>.stride, index: Int(kHeight.rawValue))

		if gridType == 1 {
			renderEncoder.setVertexBytes(&calcIsNotFreezed, length: MemoryLayout<Bool>.stride, index: Int(kIsNotFreezed.rawValue))
		}
		if gridType == 0 {
			renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: gridCurveNodeCount)
		} else {
//			renderEncoder.drawIndexedPrimitives(type: .triangleStrip,
//												indexCount: indecesBuffer.count,
//												indexType: .uint32,
//												indexBuffer: indecesBuffer.buffer,
//												indexBufferOffset: 0)
			renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: gridCurveNodeCount)
		}

	}
	
	func drawFootMetrics(_ renderEncoder:MTLRenderCommandEncoder) {
		renderEncoder.setRenderPipelineState(metricPipelineState)
		renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
		renderEncoder.setVertexBytes(&floorHeight, length: MemoryLayout<Float>.stride, index: Int(kHeight.rawValue))
		renderEncoder.setVertexBuffer(borderBuffer)
		renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: borderBuffer.count)
	}
	
	
	func drawScanningFootAsSingleFrame(_ renderEncoder:MTLRenderCommandEncoder) {
		renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
		
		renderEncoder.setRenderPipelineState(singleFramePipelineState)
		
		renderEncoder.setVertexBuffer(curveGridBuffer)
		renderEncoder.setVertexBytes(&floorHeight, length: MemoryLayout<Float>.stride, index: Int(kHeight.rawValue))
		renderEncoder.setVertexBytes(&frameAccumulated, length: MemoryLayout<Int32>.stride, index: Int(kFrame.rawValue))
//		renderEncoder.drawIndexedPrimitives(type: .point,
//											indexCount: indecesBuffer.count,
//											indexType: .uint32,
//											indexBuffer: indecesBuffer.buffer,
//											indexBufferOffset: 0)
		renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: gridCurveNodeCount)
	}
	
}
