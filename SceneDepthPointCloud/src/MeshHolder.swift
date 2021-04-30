import Foundation

class GroupedData {
	var data: [Int:String] = .init()
}

class GroupDataCoords {
	var data: [Int:[(Int, Int, Float)]] = .init()
}

class MeshHolder {
	
	let renderer: Renderer
	let dim = Int(GRID_NODE_COUNT)
	lazy var coords: GroupDataCoords = separateData()

	init(_ renderer: Renderer) {
		self.renderer = renderer
	}
	
		
	func convertToObj() -> GroupedData {
		let res = GroupedData()
		for key in coords.data.keys {
			res.data[key] = writeEdges(input: key)
		}
		let smoothedFootKey = Int(Foot.rawValue) + 1
		res.data[smoothedFootKey] = writeEdges(input: Int(Foot.rawValue), toSmooth: true)
		return res
	}
	
	// сгруппировать данные по группам (группа точек/номер кадра)
	private func separateData() -> GroupDataCoords {
		let res = GroupDataCoords()
		if renderer.currentState != .separate {	// по группам
			res.data = [ Int(Unknown.rawValue):.init(),
						 Int(Foot.rawValue):.init(),
						 Int(Floor.rawValue):.init() ]
			
			for i in 0..<renderer.myGridSphericalBuffer.count {
				let node = renderer.myGridSphericalBuffer[i]
				let row = Int(gridRow(Int32(i)))
				let col = Int(gridColumn(Int32(i)))
				let val = node.median
				res.data[Int(node.group.rawValue)]!.append( (row, col, val) )

			}
			
		} else {	// по номеру кадра
			let mn = 60
			for i in 0..<MAX_MESH_STATISTIC/Int32(mn) {
				res.data[Int(i)] = .init()
			}
			
			for frame in 0..<MAX_MESH_STATISTIC/Int32(mn) {
				for i in 0..<renderer.myGridSphericalBuffer.count {
					var node = renderer.myGridSphericalBuffer[i]
					let row = Int(gridRow(Int32(i)))
					let col = Int(gridColumn(Int32(i)))
					let val = getValue(&node, frame)
					res.data[Int(frame)]!.append( (row, col, val) )
				}
			}
		}
		
		return res
		
	}

	// упаковать данные в строку
	private func writeEdges(input key: Int, toSmooth: Bool = false) -> String {
	
		let nullsStr = "v 0 0 0\n"
		var res = ""
		var table = fullTable(key)
		if toSmooth {
			smooth(&table)
//			truncateTheFloor(table: &table)
		}

		for i in 0..<dim {
			for j in 0..<dim {
				var str = ""
				if table[i][j] != Float() {
					let pos = calcCoords(i, j, &table)
					str = "v \(pos.x) \(pos.y) \(pos.z)\n"
				} else {
					if (renderer.currentState != .separate) {
						str = nullsStr
					}
				}
				res.append(str)
			}
		}
		
		if (renderer.currentState != .separate) {
			for i in 0..<dim {
				for j in 0..<dim {
					if (table[i][j] != Float()) {
						if (j+1 != dim && table[i][j+1] != Float()) {
							let index = i*dim + j
							res.append("l \(index+1) \(index+2)\n")
						}
						if (i+1 != dim && table[i+1][j] != Float()) {
							let index = (i+1)*dim + j
							res.append("l \(index-dim+1) \(index+1)\n")
						}
					}
				}
			}
		}
		
		return res
	}
	
	private	func fullTable( _ key: Int ) -> [[Float]] {
		var res = Array(repeating:Array(repeating: Float(), count: dim), count: dim)
		for ( i, j, val ) in coords.data[key]! {
			res[i][j] = val
		}
		return res
	}
	   
	   
   private func calcCoords(_ i:Int, _  j:Int, _ table: inout [[Float]]) -> Float3 {
	   let value = table[i][j]
	   let x = -calcX(Int32(i), Int32(j), value) // flip the foot
	   let y = calcY(Int32(i), Int32(j), value)
	   let z = calcZ(Int32(i), Int32(j), value)
	   return 1000*Float3(x, y, z)
   }
   
   private func isSloped(_ r1: Float3, _ r2: Float3) -> Bool {
	   let dr = r2 - r1
	   return abs(dr.z) > sqrt(dr.x*dr.x + dr.y*dr.y)
   }
	   
	   
	   
	private func smooth(_ table: inout [[Float]]) {
		for theta in 1..<dim-1 {
			for phi in 0..<dim {
				let phi_prev = (phi-1 + dim)%dim
				let phi_next = (phi+1 + dim)%dim
				var mask:[Float] = [
						table[theta-1][phi_prev], table[theta-1][phi], table[theta-1][phi_next],
						table[theta][phi_prev],   table[theta][phi],   table[theta][phi_next],
						table[theta+1][phi_prev], table[theta+1][phi], table[theta+1][phi_next]
									]
				mask.sort()
				table[theta][phi] = mask[4]
			}
	   }
   }
	   
   private func truncateTheFloor(table: inout [[Float]]) {
	   for j_phi in 0..<dim {
		   var iStop:Int?
		   var rhoCutted:Float?
		   for i_theta in (3..<dim-1).reversed() {
			   let r1 = calcCoords(i_theta - 3, j_phi, &table)
			   let r2 = calcCoords(i_theta - 2, j_phi, &table)
			   let r3 = calcCoords(i_theta - 1, j_phi, &table)
			   let r4 = calcCoords(i_theta, j_phi, &table)
			   if isSloped(r1, r2) &&
				  isSloped(r2, r3) &&
				  isSloped(r3, r4) {
				   iStop = i_theta
				   rhoCutted = table[i_theta][j_phi]
				   break
			   }
		   }
		   if let thetaFloor = iStop,
			  let rho = rhoCutted {
			   for i_theta in thetaFloor..<dim {
				   table[i_theta][j_phi] = rho
			   }
		   }
		   
	   }
	   
   }
	
	
	
}
