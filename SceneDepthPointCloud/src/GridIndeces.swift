extension Renderer {
	
	func initializeGridIndeces(cyclic:Bool = true) -> MetalBuffer<UInt32> {

		var indecesData = [UInt32]()
		let nodeCount = (u: UInt32(U_GRID_NODE_COUNT), phi: UInt32(PHI_GRID_NODE_COUNT))

		func index(_ i:UInt32, _ j:UInt32) -> UInt32 {
			return i*nodeCount.phi + j
		}

		func UpDown(_ j: UInt32) -> [UInt32] {
			var res = [UInt32]()
			for i in 0..<nodeCount.u-1 {
				res.append( contentsOf: [index(i,j), index(i,j+1)] )
			}
			res.append(index(nodeCount.u-1,j))

			return res
		}

		func DownUp(_ j: UInt32) -> [UInt32] {
			var res = [UInt32]()
			for i in (1..<nodeCount.u).reversed() {
				if cyclic {
					res.append(contentsOf: [index(i, j%nodeCount.phi), index(i,(j+1)%nodeCount.phi)])
				} else {
					res.append(contentsOf: [index(i, j), index(i,j+1)])
				}
			}
			res.append(index(0,j))

			return res
		}

		func bottomRight() -> UInt32 {
			return index(nodeCount.u-1, nodeCount.phi-1)
		}

		func upRight() -> UInt32 {
			return index(0, nodeCount.phi-1)
		}

		let cyclicNode:UInt32 = cyclic ? 1: 0
		let endPoint:()->UInt32 = ((nodeCount.phi + cyclicNode)%2 == 0) ? bottomRight : upRight

		for j in 0..<nodeCount.phi-1 + cyclicNode {
			let move:(UInt32)->[UInt32] = (j%2 == 0) ? UpDown : DownUp
			indecesData.append(contentsOf: move(j))
		}
		indecesData.append(endPoint())
		indecesBuffer = .init(device: device, array: indecesData, index: 0)

		return indecesBuffer

	}
	
}
