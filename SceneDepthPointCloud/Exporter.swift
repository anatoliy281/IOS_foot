import UIKit

class Exporter {
	
	enum Parameter {
		case position, color
	}
	
	var savedData:[String:String] = [:]
	
	public func setBufferData(buffer: MetalBuffer<ParticleUniforms>, key:String, parameter:Parameter) {
		var str = ""
		for i in 0..<buffer.count {
			var vec: simd_float3
			if length_squared(buffer[i].position) == 0 {
				continue
			}
			if (parameter == .position) {
				vec = buffer[i].position
			} else {
				vec = buffer[i].color
			}
			str.append("v \(vec[0]) \(vec[1]) \(vec[2])\n")
		}
		savedData[key] = str
	}
	
	public func sendAllData() -> UIActivityViewController? {
		let dirs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
		if dirs.isEmpty {
			return nil
		}
		let dir = dirs.first!
		var urls:[URL] = []
		for (key, value) in savedData {
			let fileURL = dir.appendingPathComponent("\(key).obj")
			urls.append(fileURL)
			//writing
			do {
				try value.write(to: fileURL, atomically: true, encoding: String.Encoding.utf8)
			}
			catch {/* error handling here */}
		}
		let activity = UIActivityViewController(activityItems: urls, applicationActivities: .none)
		activity.isModalInPresentation = true
		return activity
	}
	
}
