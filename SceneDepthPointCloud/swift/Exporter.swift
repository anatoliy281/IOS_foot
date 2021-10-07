import UIKit

class Exporter {
	
	enum Parameter: Int {
		case position,
			 color,
			 surfaceMesh
	}
	
	var shift:Float3 = .init()
	var angle:Float = 0
	
	public func setTransformInfo(shift:Float3, angle:Float) {
		self.shift = shift
		self.angle = angle
	}
	
	typealias FileDescr = (fName:String, data:String)
	
	var savedData:[FileDescr] = []
	
	private func writeSubmesh(vertexBuffer: MetalBuffer<ParticleUniforms>,
							  sumMeshIndeces: MetalBuffer<UInt32>) -> String {
		var vertStr = ""
		var vertCount = 0
		for i in 0..<vertexBuffer.count {
			let p = vertexBuffer[i].position
			if length_squared(p) == 0 { continue }
			let pTrnsf = transform(point: p)
			vertCount += 1
			vertStr.append("\(pTrnsf[0]) \(pTrnsf[1]) \(pTrnsf[2])\n")
		}
		// индексы сетки
		var indecesStr = ""
		var indecesCount = 0
		for i in stride(from: 0, to: sumMeshIndeces.count-3, by: 3) {
			if sumMeshIndeces[i] ==  0 && sumMeshIndeces[i+1] == 0 && sumMeshIndeces[i+2] == 0 { continue }
			indecesCount += 1
			indecesStr.append("3 \(sumMeshIndeces[i]) \(sumMeshIndeces[i+1]) \(sumMeshIndeces[i+2])\n")
		}
		let capStr = "OFF\n\(vertCount) \(indecesCount) 0\n"
		return capStr + vertStr + indecesStr
	}
	
	func transform(point:simd_float3) -> simd_float3 {
		
		let px = point.x
		let py = point.y
		let pz = point.z
		
		let pShifted = point - shift
		
		let psx = pShifted.x
		let psy = pShifted.y
		let psz = pShifted.z
		
		let p2 = simd_float2(pShifted.x, -pShifted.z);
		let z = -pShifted.y
		
		let m:simd_float2x2 = .init(
			simd_float2(cos(angle), sin(angle)),
			simd_float2(-sin(angle), cos(angle))
		)
		
		let p2_rot = m*p2
		
		return simd_float3(p2_rot.x, p2_rot.y, z);
	}
	
	public func setBufferData(buffer: MetalBuffer<ParticleUniforms>,
							  parameter:Parameter,
							  indeces: [UInt32:MetalBuffer<UInt32>]?) {
		var fileName = ""
		var fileContent = ""
		if (parameter == .surfaceMesh) {
			fileName = "mesh.off";
			fileContent = writeSubmesh(vertexBuffer: buffer,
									   sumMeshIndeces:indeces![Undefined.rawValue]!)
			savedData.append( FileDescr(fileName, fileContent) )
			fileName = "floor.off";
			fileContent = writeSubmesh(vertexBuffer: buffer,
									   sumMeshIndeces:indeces![Floor.rawValue]!)
			savedData.append( FileDescr(fileName, fileContent) )
			fileName = "foot.off";
			fileContent = writeSubmesh(vertexBuffer: buffer,
									   sumMeshIndeces:indeces![Foot.rawValue]!)
			savedData.append( FileDescr(fileName, fileContent) )
		} else {
			fileName = (parameter == .position) ? "cloud.obj" : "color.obj"
			for i in 0..<buffer.count {
				var vec: simd_float3
				if length_squared(buffer[i].position) == 0 { continue }
				if (parameter == .position) {
					vec = buffer[i].position
					vec = transform(point: vec)
				} else {
					vec = buffer[i].color
				}
				fileContent.append("v \(vec[0]) \(vec[1]) \(vec[2])\n")
			}
			savedData.append( FileDescr(fileName, fileContent) )
		}
		
	}
	
	public func sendAllData() -> UIActivityViewController? {
		let dirs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
		if dirs.isEmpty {
			return nil
		}
		let dir = dirs.first!
		var urls:[URL] = []
		for value in savedData {
			let fileURL = dir.appendingPathComponent(value.fName)
			urls.append(fileURL)
			do {
				try value.data.write(to: fileURL, atomically: true, encoding: String.Encoding.utf8)
			}
			catch {/* error handling here */}
		}
		let activity = UIActivityViewController(activityItems: urls, applicationActivities: .none)
		activity.isModalInPresentation = true
		return activity
	}
	
}
