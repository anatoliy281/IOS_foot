import Foundation

class GroupedData {
	var data: [Int:String] = .init()
}

class GroupDataCoords {
	var data: [Int:[(Int, Int, Float)]] = .init()
}

class MeshHolder {
	
	var table: [[Float]] = [] // содержит текущую таблицу узлов
//	var thisLayer:Int = 0 {
//		willSet {
//			cutContourId = Int(Foot.rawValue) + newValue + 3
//			contoursId.removeAll(where: {$0 == cutContourId})
//		}
//	}
//	var layersNumber: Int = 0 {
//		willSet {
//			for i in 0..<newValue {
//				contoursId.append(i + Int(Foot.rawValue) + 3)
//			}
//		}
//	}
	var cutHeight: Float = 0
	
	
	let renderer: Renderer
	let dim:Int2 = .init( 2*Int(U_GRID_NODE_COUNT),
						  Int(PHI_GRID_NODE_COUNT) )
	lazy var coords: GroupDataCoords = separateData()
	
	var contoursId: [Int] = []	// содержит id контуров (для отладки)
	var cutContourId: Int = -1		// id контура среза
	var debugMeshesId: [Int] = [Int(Foot.rawValue) + 1, Int(Foot.rawValue) + 2]  // содержит id временных сеток (для отладки)

	init(_ renderer: Renderer) {
		self.renderer = renderer
	}
	
		
	func convertToObj() -> GroupedData {
		let res = GroupedData()
		
		for key in coords.data.keys {
			res.data[key] = writeEdges(input: key)
		}
		
		return res
	}
	
	// сгруппировать данные по группам (группа точек/номер кадра)
	private func separateData() -> GroupDataCoords {
		let res = GroupDataCoords()

		res.data = [ Int(Unknown.rawValue):.init(),
					 Int(Floor.rawValue):.init(),
					 Int(Border.rawValue):.init(),
					 Int(Foot.rawValue):.init(),
					 Int(ZoneUndefined.rawValue):.init()
		]

		let buffer = renderer.curveGridBuffer!.buffer

		for i in 0..<buffer.count { // перебор узлов текущей сетки
			let node = buffer[i]
			let row = Int(gridRow(Int32(i)))
			let col = Int(gridColumn(Int32(i)))
			let val = node.mean
			res.data[Int(node.group.rawValue)]!.append( (row, col, val) )

		}

		return res

	}

	// упаковать данные в строку
	private func writeEdges(input key: Int) -> String {
		fullTable(key)
		return writeNodes()
	}
	
	private	func fullTable( _ key: Int ) {
		table = Array(repeating:Array(repeating: Float(), count: dim.y), count: dim.x)
		for ( i, j, val ) in coords.data[key]! {
			table[i][j] = val
		}
	}
	   
	let k:Float = 1
	let h0:Float = -0.03
	let dU = Float(LENGTH*LENGTH) / Float(U0_GRID_NODE_COUNT + U1_GRID_NODE_COUNT)
	let dPhi = 2*Float.pi / Float(PHI_GRID_NODE_COUNT)
	
	let hl:Float = Float(BOX_HALF_LENGTH)
	let hw:Float = Float(BOX_HALF_WIDTH)
	let bh:Float = Float(BOX_HEIGHT)
	
	lazy var shiftsCS:[simd_float3] = [
		simd_float3(-hl, -hw, 0),
		simd_float3(  0, -hw, 0),
		simd_float3( hl, -hw, 0),
		simd_float3( hl,  hw, 0),
		simd_float3(  0,  hw, 0),
		simd_float3(-hl,  hw, 0)
	]
	
	private func inFootFrame(_ spos:simd_float3) -> Bool {
		let checkWidth = abs(spos.y) < hw;
		let checkLength = abs(spos.x) < hl;
		let checkHeight = abs(spos.z) < bh;
		return checkWidth && checkLength && checkHeight;
	}
	
	private func calcCoords(_ i:Int, _ j:Int, _ value:Float ) -> Float3 {
		
		
//		let u_coord = Float( i - Int(U0_GRID_NODE_COUNT) )*dU;
//		let v_coord = value;
		let u_coord = value;
		
		let iShift = ( i > Int(U_GRID_NODE_COUNT) ) ? Int(U_GRID_NODE_COUNT): 0;
		
		let v_coord = Float(i - iShift)*dU;
		
		let uv_sqrt = sqrt(k*k*v_coord*v_coord + u_coord*u_coord);
		let rho = sqrt(0.5*(u_coord + uv_sqrt)) / k;
		let h = sqrt(k*k*rho*rho - u_coord) + h0;
		
		
		let phi = Float(j)*dPhi;
		// flip the foot
		var pos = Float3(rho*cos(phi), rho*sin(phi), h)
		
		if iShift == 0 {
			if ( (Float.pi < phi) && (phi <= 1.5*Float.pi) ) {
				pos += shiftsCS[3];
			} else if ( (1.5*Float.pi < phi) && (phi <= 2*Float.pi) ) {
				pos += shiftsCS[5];
			} else if ( (0 < phi) && (phi <= 0.5*Float.pi) ) {
				pos += shiftsCS[0];
			} else if ( (0.5*Float.pi < phi) && (phi <= Float.pi) ) {
				pos += shiftsCS[2];
			}
//				else { // так не бывает...
//				return float4();
//			}
			
		} else {
			if ( (Float.pi < phi) && (phi <= 2*Float.pi) ) {
				pos += shiftsCS[4];
			} else {
				pos += shiftsCS[1];
			}
	//		else { // и так тоже...
	//			return float4(1);
	//		}
		}
		
//		if ( (Float.pi < phi) && (phi <= 1.5*Float.pi) ) {
//			pos += shiftsCS[2];
//		} else if ( (1.5*Float.pi < phi) && (phi <= 2*Float.pi) ) {
//			pos += shiftsCS[3];
//		} else if ( (0 < phi) && (phi <= 0.5*Float.pi) ) {
//			pos += shiftsCS[0];
//		} else if ( (0.5*Float.pi < phi) && (phi <= Float.pi) ) {
//			pos += shiftsCS[1];
//		}
		
		if !inFootFrame(pos) {
			pos = .zero
		} else {	// flip the coord sys
			pos.x *= -1;
		}
		return 1000*pos	// to mm
	}
	   
	   
	   
//	private func smooth() {
//		for theta in 1..<dim.x-1 {
//			for phi in 0..<dim.y {
//				let phi_prev = (phi-1 + dim)%dim
//				let phi_next = (phi+1 + dim)%dim
//				var mask:[Float] = [
//						table[theta-1][phi_prev], table[theta-1][phi], table[theta-1][phi_next],
//						table[theta][phi_prev],   table[theta][phi],   table[theta][phi_next],
//						table[theta+1][phi_prev], table[theta+1][phi], table[theta+1][phi_next]
//									]
//				mask.sort()
//				table[theta][phi] = mask[4]
//			}
//	   }
//   }

	
	private func writeNodes() -> String {
		var res:String = ""
		for i in 0..<dim.x {
			for j in 0..<dim.y {
				var str = ""
				if table[i][j] != Float() {
					let pos = calcCoords(i, j, table[i][j])
					str = "v \(pos.x) \(pos.y) \(pos.z)\n"
				}
				res.append(str)
			}
		}

		for i in 0..<dim.x {
			for j in 0..<dim.y {
				if (table[i][j] != Float()) {
					if (j+1 != dim.y && table[i][j+1] != Float()) {
						let index = i*dim.y + j
						res.append("l \(index+1) \(index+2)\n")
					}
					if (i+1 != dim.x && table[i+1][j] != Float()) {
						let index = (i+1)*dim.y + j
						res.append("l \(index-dim.y+1) \(index+1)\n")
					}
				}
			}
		}


		return res
	}
	
	private func writeNodes(_ coords: [Float3], connectNodes:Bool = true) -> String {
		var res:String = ""
		for i in 0..<coords.count {
			var str = ""
			if coords[i] != Float3() {
				str = "v \(coords[i].x) \(coords[i].y) \(coords[i].z)\n"
			} else {
				str = "v 0 0 0\n"
			}
			res.append(str)
		}
		
		if connectNodes {
			for i in 0..<coords.count { // нужно для вывода контуров
				res.append("l \(i + 1) \((i+1)%coords.count + 1)\n")	// обрабатываем случай замыкания контура
			}
		}
		
		return res
	}
	
}
