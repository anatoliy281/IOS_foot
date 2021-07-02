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
//		renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
		renderEncoder.setVertexBytes(&pointCloudUniforms, length: MemoryLayout<CoordData>.stride, index: Int(kPointCloudUniforms.rawValue))
		
		guard let submesh = heelAreaMesh.submeshes.first else { return }
		renderEncoder.drawIndexedPrimitives(type: .triangle,
											indexCount: submesh.indexCount,
											indexType: submesh.indexType,
											indexBuffer: submesh.indexBuffer.buffer,
											indexBufferOffset: submesh.indexBuffer.offset)
	}
	
	func drawMesh(_ renderEncoder:MTLRenderCommandEncoder) {
		for i in 0..<curveGridBuffers.count {
			let cgb = curveGridBuffers[i]		// текущая сетка
			renderEncoder.setRenderPipelineState(curvedGridPipelineState)
			pointCloudUniforms.coordShift = cgb.coordCenter		// передача смещения ЛКС
			renderEncoder.setVertexBytes(&pointCloudUniforms, length: MemoryLayout<CoordData>.stride, index: Int(kPointCloudUniforms.rawValue))
		
			renderEncoder.setVertexBuffer(cgb.buffer)	// ... сетки
		
		

		
			renderEncoder.setVertexBytes(&calcIsNotFreezed, length: MemoryLayout<Bool>.stride, index: Int(kIsNotFreezed.rawValue))

			renderEncoder.drawIndexedPrimitives(type: .triangleStrip,
													indexCount: indecesBuffer.count,
													indexType: .uint32,
													indexBuffer: indecesBuffer.buffer,
													indexBufferOffset: 0)
		}
//		renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: gridCurveNodeCount)

	}
	
	func drawFootMetrics(_ renderEncoder:MTLRenderCommandEncoder) {
		for i in 0..<curveGridBuffers.count {
			let borderBuffer = curveGridBuffers[i].borderPoints
			pointCloudUniforms.coordShift = curveGridBuffers[i].coordCenter // TODO учесть в borderPoints смещённый центр?
			renderEncoder.setRenderPipelineState(metricPipelineState)

			renderEncoder.setVertexBytes(&pointCloudUniforms, length: MemoryLayout<CoordData>.stride, index: Int(kPointCloudUniforms.rawValue))
			renderEncoder.setVertexBuffer(borderBuffer)
			renderEncoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: borderBuffer.count)
			renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: borderBuffer.count)
		}
		
		let borderBuffer = metricPoints
		pointCloudUniforms.coordShift = .zero	// пока так...
		renderEncoder.setRenderPipelineState(metricPipelineState)

		renderEncoder.setVertexBytes(&pointCloudUniforms, length: MemoryLayout<CoordData>.stride, index: Int(kPointCloudUniforms.rawValue))
		renderEncoder.setVertexBuffer(borderBuffer)
		renderEncoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: borderBuffer.count)
		renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: borderBuffer.count)
	}
	
}
