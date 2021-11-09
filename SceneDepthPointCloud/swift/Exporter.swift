import UIKit

class Exporter {
	
	enum Parameter: Int {
		case position,
			 color,
			 surfaceMesh
	}
	
	var shift:Float3 = .init()
	var axes:[Float2] = .init()
	var footContour:[Float3] = []
	
	public func setTransformInfo(cppCaller caller:CPPCaller) {
		shift = [caller.getXYO(0),caller.getFloorShift(),caller.getXYO(1)]
		axes = [[caller.getDirection(0,0), caller.getDirection(0,1)],
					 [caller.getDirection(1,0), caller.getDirection(1,1)]]
	}
	
	typealias FileDescr = (fName:String, data:String)
	
	var savedData:[FileDescr] = []
	
	private func writeSubmesh(fileName: String,
							  vertexBuffer: MetalBuffer<ParticleUniforms>,
							  sumMeshIndeces: MetalBuffer<UInt32>) -> FileDescr {
		var vertStr = ""
		var vertCount = 0
		for i in 0..<vertexBuffer.count {
			let p = vertexBuffer[i].position
			if length_squared(p) == 0 { continue }
			let pTrnsf = transform2(point: p)
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
		let content = capStr + vertStr + indecesStr
		return (fileName, content)
	}
	
	func transform2(point:simd_float3) -> simd_float3 {
		
		let pShifted = point - shift
		
		let p2 = simd_float2(pShifted.x, pShifted.z);
		let z = pShifted.y
        
        let m:simd_float2x2 = .init( rows: axes )
		
		let p2_rot = m*p2
		
		return simd_float3(p2_rot.x, -p2_rot.y, z)
	
	}
	
	public func writeAxis() {
		
		for comp in 0..<axes.count {
			var content = ""

			let e = axes[comp]
			let ep = shift + simd_float3(e[0], 0, e[1])
			content.append("v \(shift[0]) \(shift[1]) \(shift[2])\n")
			content.append("v \(ep[0]) \(ep[1]) \(ep[2])\n")
			
			savedData.append(FileDescr("debugAxesTransform_\(comp).obj", content))
		}
	}
	
	public func setBufferData(buffer: MetalBuffer<ParticleUniforms>,
							  parameter:Parameter,
							  indeces: [UInt32:MetalBuffer<UInt32>]?) {
		var fileName = ""
		var fileContent = ""
		if (parameter == .surfaceMesh) {
			let meshDesc = writeSubmesh(fileName: "mesh.off",
									   vertexBuffer: buffer,
									   sumMeshIndeces:indeces![Undefined.rawValue]!)
			savedData.append(meshDesc)
			
			let floorDesc = writeSubmesh(fileName: "floor.off",
									   vertexBuffer: buffer,
									   sumMeshIndeces:indeces![Floor.rawValue]!)
			savedData.append(floorDesc)
			
			let footDesc = writeSubmesh(fileName: "foot.off",
									   vertexBuffer: buffer,
									   sumMeshIndeces:indeces![Foot.rawValue]!)
			savedData.append(footDesc)
			
			let polisheDesc = writeSubmesh(fileName: "polished_foot.off",
									   vertexBuffer: buffer,
									   sumMeshIndeces:indeces![PolishedFoot.rawValue]!)
			savedData.append(polisheDesc)
		} else {
			fileName = (parameter == .position) ? "cloud.obj" : "color.obj"
			for i in 0..<buffer.count {
				var vec: simd_float3
				if length_squared(buffer[i].position) == 0 { continue }
				if (parameter == .position) {
					vec = buffer[i].position
					let vecTrnsf = transform2(point: vec)
					vec = vecTrnsf
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
	
	public func setFootContour(cppCaller caller:CPPCaller) {
		for i in 0..<caller.getContourSize() {
			let p = Float3(caller.getContourPoint(i, 0),
						   caller.getContourPoint(i, 1),
						   caller.getContourPoint(i, 2))
			footContour.append(p)
		}
	}
	
	public func writeFootContour() {
		var content = ""
		for p in footContour {
			content.append("v \(p[0]) \(p[1]) \(p[2])\n")
		}
		savedData.append(FileDescr("footContour.obj", content))
	}
	
	
	public func write2DHistogram(cppCaller caller:CPPCaller) {
		
		var content = ""
		
		for i in 0..<caller.get2DHistoSize() {
			let p = Float3(caller.get2DHistoPoint(i, 0),
						   caller.get2DHistoPoint(i, 1),
						   caller.get2DHistoPoint(i, 2))
			content.append("v \(p[0]) \(p[1]) \(p[2])\n")
		}
		savedData.append(FileDescr("foot2DHistogram.obj", content))
	}
	
	
}
