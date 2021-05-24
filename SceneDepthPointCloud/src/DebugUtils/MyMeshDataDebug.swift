import MetalKit

enum MeshDataField {
	case median, length, pairs, pairLen
}

func debugNode(node:Int, buffer:MTLBuffer, field: MeshDataField) {
	let meshData = buffer.contents().load(fromByteOffset: MemoryLayout<MyMeshData>.stride*node, as: MyMeshData.self)
	switch (field) {
	case .median:
		print("median: \(meshData.mean)")
	case .length:
		print("position: \(meshData.bufModLen) / \(meshData.totalSteps)")
	case .pairs:
		var pairs = [Float].init()
		if (meshData.pairLen == 1) {
			pairs.append(meshData.pairs.0)
		}
		if meshData.pairLen == 2 {
			pairs.append(meshData.pairs.1)
		}
		print("pairs: \(pairs)")
		
	case .pairLen:
		print("pair length: \(meshData.pairLen)")
	}

	
}
