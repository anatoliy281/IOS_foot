import Foundation

class GroupedData {
	var data: [Int:String] = .init()
}

class GroupDataCoords {
	var data: [Int:[(Int, Int, Float)]] = .init()
}



class MeshHolder {
	//  Т.к таблица хранит фактически 2 сетки, размер tableSize по U_GRID_NODE_COUNT увеличен вдвое
	let dV:Float = Float(U_STEP)
	let dPhi:Float = 2*Float.pi / Float(PHI_GRID_NODE_COUNT)
	
	let hl:Float = Float(BOX_HALF_LENGTH)
	let hw:Float = Float(BOX_HALF_WIDTH)
	let bh:Float = Float(BOX_HEIGHT)
	
	let tableSize:(V:Int, Phi:Int)
	var table: [[Float]] = [] // содержит переформатированную таблицу узлов	let h0:Float = -0.03
	
	let shiftsCS:[simd_float3]
	
	let renderer: Renderer
	lazy var coords: GroupDataCoords = separateData()

	init(_ renderer: Renderer) {
		self.renderer = renderer
		tableSize = ( 2*Int(U_GRID_NODE_COUNT), Int(PHI_GRID_NODE_COUNT) )
		shiftsCS = [
			   simd_float3(-hl, -hw, 0),
			   simd_float3(  0, -hw, 0),
			   simd_float3( hl, -hw, 0),
			   simd_float3( hl,  hw, 0),
			   simd_float3(  0,  hw, 0),
			   simd_float3(-hl,  hw, 0)
		   ]
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
			let row = gridRow(i)
			let col = gridColumn(i)
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
		table = Array(repeating:Array(repeating: Float(), count: tableSize.Phi), count: tableSize.V)
		for ( i, j, val ) in coords.data[key]! {
			table[i][j] = val
		}
	}
	
	private func inFootFrame(_ spos:simd_float3) -> Bool {
		let checkWidth = abs(spos.y) < hw;
		let checkLength = abs(spos.x) < hl;
		let checkHeight = abs(spos.z) < bh;
		return checkWidth && checkLength && checkHeight;
	}
	
	private func calcCoords(_ i:Int, _ j:Int, _ value:Float ) -> Float3 {
		let k:Float = 1
		let h0:Float = -0.03
		
		let u_coord = value;
		
		let isSecondTable = i > tableSize.V / 2;
		
		let iShift = isSecondTable ? tableSize.V / 2 : 0;
		
		let v_coord = Float(i - iShift)*dV;
		
		let uv_sqrt = sqrt(k*k*v_coord*v_coord + u_coord*u_coord);
		let rho = sqrt(0.5*(u_coord + uv_sqrt)) / k;
		let h = sqrt(k*k*rho*rho - u_coord) + h0;
		
		
		let phi = Float(j)*dPhi;
		// flip the foot
		var pos = Float3(rho*cos(phi), rho*sin(phi), h)
		
		if isSecondTable {
			if ( (Float.pi < phi) && (phi <= 2*Float.pi) ) {
				pos += shiftsCS[4];
			} else {
				pos += shiftsCS[1];
			}
		} else {
			if ( (Float.pi < phi) && (phi <= 1.5*Float.pi) ) {
				pos += shiftsCS[3];
			} else if ( (1.5*Float.pi < phi) && (phi <= 2*Float.pi) ) {
				pos += shiftsCS[5];
			} else if ( (0 < phi) && (phi <= 0.5*Float.pi) ) {
				pos += shiftsCS[0];
			} else if ( (0.5*Float.pi < phi) && (phi <= Float.pi) ) {
				pos += shiftsCS[2];
			}
			
		}
		
		if !inFootFrame(pos) {
			pos = .zero
		} else {	// flip the coord sys
			pos.x *= -1;
		}
		return 1000*pos	// to mm
	}

	
	private func writeNodes() -> String {
		var res:String = ""
		for i in 0..<tableSize.V {
			for j in 0..<tableSize.Phi {
				var str = ""
				if table[i][j] != Float() {
					let pos = calcCoords(i, j, table[i][j])
					str = "v \(pos.x) \(pos.y) \(pos.z)\n"
				}
				res.append(str)
			}
		}

		for i in 0..<tableSize.V {
			for j in 0..<tableSize.Phi {
				if (table[i][j] != Float()) {
					if (j+1 != tableSize.Phi && table[i][j+1] != Float()) {
						let index = i*tableSize.Phi + j
						res.append("l \(index+1) \(index+2)\n")
					}
					if (i+1 != tableSize.V && table[i+1][j] != Float()) {
						let index = (i+1)*tableSize.Phi + j
						res.append("l \(index-tableSize.Phi+1) \(index+1)\n")
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
