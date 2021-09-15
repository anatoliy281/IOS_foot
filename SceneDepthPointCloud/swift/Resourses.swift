class Resourses {
	let r:Float = 0.02
	var bufferSquare:[ParticleUniforms]
	init() {
		let white:Float3 = .one
		bufferSquare = [
			ParticleUniforms(position: .zero, color: white, confidence: 2),						// 0
			ParticleUniforms(position: .zero, color: white, confidence: 2),						// 1
			ParticleUniforms(position: .zero, color: white, confidence: 2),						// 2
			ParticleUniforms(position: .zero, color: white, confidence: 2),						// 3
			ParticleUniforms(position: .zero, color: white, confidence: 2),						// 4
			ParticleUniforms(position: .zero, color: white, confidence: 2),						// 5
			ParticleUniforms(position: Float3(-r, 0, -r), color: white, confidence: 2),			// 6*
			ParticleUniforms(position: .zero, color: white, confidence: 2),						// 7
			ParticleUniforms(position: .zero, color: white, confidence: 2),						// 8
			ParticleUniforms(position: .zero, color: white, confidence: 2),						// 9*
			ParticleUniforms(position: Float3(-r, 0,  r), color: white, confidence: 2),			// 10*
			ParticleUniforms(position: Float3( r, 0,  r), color: white, confidence: 2),			// 11*
			ParticleUniforms(position: .zero, color: white, confidence: 2),						// 12
			ParticleUniforms(position: Float3( r, 0, -r), color: white, confidence: 2),			// 13*
			ParticleUniforms(position: .zero, color: white, confidence: 2),						// 14
			ParticleUniforms(position: .zero, color: white, confidence: 2),						// 15
			ParticleUniforms(position: .zero, color: white, confidence: 2)						// 16
		]
	}
}

