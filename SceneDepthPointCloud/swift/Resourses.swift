class Resourses {
	let r:Float = 0.02
	var bufferSquare:[ParticleUniforms]
	init() {
		let white:Float3 = .one
		bufferSquare = [
			ParticleUniforms(position: .zero, color: white),						// 0
			ParticleUniforms(position: .zero, color: white),						// 1
			ParticleUniforms(position: .zero, color: white),						// 2
			ParticleUniforms(position: .zero, color: white),						// 3
			ParticleUniforms(position: .zero, color: white),						// 4
			ParticleUniforms(position: .zero, color: white),						// 5
			ParticleUniforms(position: Float3(-r, 0, -r), color: white),			// 6*
			ParticleUniforms(position: .zero, color: white),						// 7
			ParticleUniforms(position: .zero, color: white),						// 8
			ParticleUniforms(position: .zero, color: white),						// 9*
			ParticleUniforms(position: Float3(-r, 0,  r), color: white),			// 10*
			ParticleUniforms(position: Float3( r, 0,  r), color: white),			// 11*
			ParticleUniforms(position: .zero, color: white),						// 12
			ParticleUniforms(position: Float3( r, 0, -r), color: white),			// 13*
			ParticleUniforms(position: .zero, color: white),						// 14
			ParticleUniforms(position: .zero, color: white),						// 15
			ParticleUniforms(position: .zero, color: white)							// 16
		]
	}
}

