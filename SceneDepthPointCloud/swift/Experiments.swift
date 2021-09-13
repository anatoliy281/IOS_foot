import Foundation

extension Renderer {
	
	func showIndexBuffer(buffer:MetalBuffer<UInt64>) {
		for i in 0..<buffer.count {
			if i%3 == 0 && i != 0 {
				print()
			}
			print("\(buffer[i]) ")
		}
	}
	
	func testBufferModifications () {
		let arrIn:[ParticleUniforms] =
			[ParticleUniforms(position: Float3(-1.0, -1.0, 0.0), color: Float3(1,1,1), confidence: 2),
			 ParticleUniforms(position: Float3(-1.0,  1.0, 0.0), color: Float3(1,1,1), confidence: 2),
			 ParticleUniforms(position: Float3( 1.0,  1.0, 0.0), color: Float3(1,1,1), confidence: 2),
			 ParticleUniforms(position: Float3( 1.0, -1.0, 0.0), color: Float3(1,1,1), confidence: 2),
			 ParticleUniforms(position: Float3( 0.0,  0.0, 0.0), color: Float3(1,1,1), confidence: 2)
			]
		let testPointBuf:MetalBuffer<ParticleUniforms> = .init(device: device,
															   array: arrIn, index: 0)
		let trianglesCount = 4
		let vertexInTriangle = 3
		var testIndexBuf:MetalBuffer<UInt64> = .init(device: device,
															   count: trianglesCount*vertexInTriangle, index: 0)
//		showIndexBuffer(buffer: testIndexBuf)
		caller.triangulate(testPointBuf.buffer, testIndexBuf.buffer)
		showIndexBuffer(buffer: testIndexBuf)
	}
}
