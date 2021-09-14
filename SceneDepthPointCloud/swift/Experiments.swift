import Foundation

extension Renderer {
	
	func showIndexBuffer(buffer:MetalBuffer<UInt32>) {
		print("buffer begin")
		for i in stride(from: 0, to: buffer.count-2, by: 3) {
			if (buffer[i] == 0 && buffer[i+1] == 0 && buffer[i+2] == 0) {
				continue
			} else {
				print("{\(i)} \(buffer[i]) \(buffer[i+1]) \(buffer[i+2])")
			}
		}
		print("buffer end")
	}
	
	func testBufferModifications () {
		let arrIn:[ParticleUniforms] =
		[
			ParticleUniforms(position: Float3(0, 0, 0), color: Float3(1,1,1), confidence: 2),			// 0
			ParticleUniforms(position: Float3(0, 0, 0), color: Float3(1,1,1), confidence: 2),			// 1
			ParticleUniforms(position: Float3(0, 0, 0), color: Float3(1,1,1), confidence: 2),			// 2
			ParticleUniforms(position: Float3(0, 0, 0), color: Float3(1,1,1), confidence: 2),			// 3
			ParticleUniforms(position: Float3(0, 0, 0), color: Float3(1,1,1), confidence: 2),			// 4
			ParticleUniforms(position: Float3(0, 0, 0), color: Float3(1,1,1), confidence: 2),			// 5
			ParticleUniforms(position: Float3(-1.0, -1.0, 0.0), color: Float3(1,1,1), confidence: 2),	// 6*
			ParticleUniforms(position: Float3(0, 0, 0), color: Float3(1,1,1), confidence: 2),			// 7
			ParticleUniforms(position: Float3(0, 0, 0), color: Float3(1,1,1), confidence: 2),			// 8
			ParticleUniforms(position: Float3(0, 0, 0), color: Float3(1,1,1), confidence: 2),			// 9*
			ParticleUniforms(position: Float3(-1.0,  1.0, 0.0), color: Float3(1,1,1), confidence: 2),	// 10*
			ParticleUniforms(position: Float3( 1.0,  1.0, 0.0), color: Float3(1,1,1), confidence: 2),	// 11*
			ParticleUniforms(position: Float3(0, 0, 0), color: Float3(1,1,1), confidence: 2),			// 12
			ParticleUniforms(position: Float3( 1.0, -1.0, 0.0), color: Float3(1,1,1), confidence: 2),	// 13*
			ParticleUniforms(position: Float3(0, 0, 0), color: Float3(1,1,1), confidence: 2),			// 14
			ParticleUniforms(position: Float3(0, 0, 0), color: Float3(1,1,1), confidence: 2),			// 15
			ParticleUniforms(position: Float3(0, 0, 0), color: Float3(1,1,1), confidence: 2)			// 16
		]
		let testPointBuf:MetalBuffer<ParticleUniforms> = .init(device: device,
															   array: arrIn, index: 0)
		let trianglesCount = 4
		let vertexInTriangle = 3
		var testIndexBuf:MetalBuffer<UInt32> = .init(device: device,
															   count: trianglesCount*vertexInTriangle, index: 0)
//		showIndexBuffer(buffer: testIndexBuf)
		caller.triangulate(testPointBuf.buffer, testIndexBuf.buffer)
		showIndexBuffer(buffer: testIndexBuf)
	}
}
