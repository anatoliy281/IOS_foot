import Foundation

class GroupedData {
	var data: [Int:String] = .init()
}

class GroupDataCoords {
	var data: [Int:[(Int, Int, Float)]] = .init()
}

class MeshHolder {
	
	var table: [[Float]] = [] // содержит текущую таблуцу узлов
	var thisLayer:Int = 0 {
		willSet {
			cutContourId = Int(Foot.rawValue) + newValue + 3
			contoursId.removeAll(where: {$0 == cutContourId})
		}
	}
	var layersNumber: Int = 0 {
		willSet {
			for i in 0..<newValue {
				contoursId.append(i + Int(Foot.rawValue) + 3)
			}
		}
	}
	var cutHeight: Float = 0
	
	
	let renderer: Renderer
//	let dim = Int(Z_GRID_NODE_COUNT)
	lazy var coords: GroupDataCoords = separateData()
	
	var contoursId: [Int] = []	// содержит id контуров (для отладки)
	var cutContourId: Int = -1		// id контура среза
	var debugMeshesId: [Int] = [Int(Foot.rawValue) + 1, Int(Foot.rawValue) + 2]  // содержит id временных сеток (для отладки)

	init(_ renderer: Renderer) {
		self.renderer = renderer
	}
	
		
//	func convertToObj() -> GroupedData {
//		let res = GroupedData()
//		// не выводим сетки по типу узла
////		for key in coords.data.keys {
////			res.data[key] = writeEdges(input: key)[0]
////		}
//		
//		// а выводим только сетки ноги и их контуры
//		let meshesAndContours = writeEdges( input: Int(Foot.rawValue), toSmooth: true, toTruncFloor: true )
//		// вывод контуров сперва исходный, затем сглаженный -> обрезанный -> контуры
//		for i in 0..<meshesAndContours.count {
//			let contourId = Int(Foot.rawValue) + i
//			res.data[contourId] = meshesAndContours[i]	// исходная сетка i = 0 (id = 2), сглаженная i = 1 (id = 3), обрезанная i = 2 (id = 4), слои i = 3,4,... (id = 5, 6, ...)
////			if 1 <= i && i <= 2 { // i = 1, 2 (id = 3, 4)
////				debugMeshesId.append(contourId)
////			} else {
////				if contourId != cutContourId { // контуры начинаются отсчитываться с 3 позиции i = 3 (номер контура или слоя 0)
////					contoursId.append(contourId)
////				}
////
////			}
//		}
//		
//		return res
//	}
	
	// сгруппировать данные по группам (группа точек/номер кадра)
	private func separateData() -> GroupDataCoords {
		let res = GroupDataCoords()
		if renderer.currentState != .separate {	// по группам
			res.data = [ Int(Unknown.rawValue):.init(),
						 Int(Foot.rawValue):.init(),
						 Int(Floor.rawValue):.init() ]
			
			for i in 0..<renderer.cylindricalGridBuffer.count {
				let node = renderer.cylindricalGridBuffer[i]
				let row = Int(gridRow(Int32(i)))
				let col = Int(gridColumn(Int32(i)))
				let val = node.mean
				res.data[Int(node.group.rawValue)]!.append( (row, col, val) )

			}
			
		} else {	// по номеру кадра
			let mn = 60
			for i in 0..<MAX_MESH_STATISTIC/Int32(mn) {
				res.data[Int(i)] = .init()
			}
			
			for frame in 0..<MAX_MESH_STATISTIC/Int32(mn) {
				for i in 0..<renderer.cylindricalGridBuffer.count {
					var node = renderer.cylindricalGridBuffer[i]
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
//	private func writeEdges(input key: Int = Int(Foot.rawValue),
//							toSmooth: Bool = false,
//							toTruncFloor: Bool = false) -> [String] {
//		fullTable(Int(Foot.rawValue))
//		var resArr:[String] = [writeNodes()]
//
//		if toSmooth {
//			smooth()
//			resArr.append(writeNodes())
//		}
//
//		if toTruncFloor {
//			let meshAndContoursCoords = truncateTheFloor()
//			resArr.append(writeNodes(meshAndContoursCoords.last!, connectNodes: false)) // выводим обрезанную сетку
//			for i in 0..<meshAndContoursCoords.count-1 {		// выводим контуры
//				resArr.append(writeNodes(meshAndContoursCoords[i]))
//			}
//
//		}
//
//
//		return resArr
//	}
	
//	private	func fullTable( _ key: Int ) {
//		table = Array(repeating:Array(repeating: Float(), count: dim), count: dim)
//		for ( i, j, val ) in coords.data[key]! {
//			table[i][j] = val
//		}
//	}
	   
	   
   private func calcCoords(_ i:Int, _  j:Int, _ table: inout [[Float]]) -> Float3 {
		let value = table[i][j]
//	   let x = -calcX(Int32(i), Int32(j), value) // flip the foot
//	   let y = calcY(Int32(i), Int32(j), value)
//	   let z = calcZ(Int32(i), Int32(j), value)
	
		let x = -calcX(Int32(j), value) // flip the foot
		let y = calcY(Int32(j), value)
		let z = calcZ(Int32(i))
	
		return 1000*Float3(x, y, z)
   }
   
	private func deriv(_ r1: Float3, _ r2: Float3) -> (rho:Float, h:Float) {
	   let dr = r2 - r1
	   return ( sqrt(dr.x*dr.x + dr.y*dr.y), abs(dr.z) )
   }
	   
	   
	   
//	private func smooth() {
//		for theta in 1..<dim-1 {
//			for phi in 0..<dim {
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
	   
//	private func truncateTheFloor(table: inout [[Float]]) {
////		let k0 = Float(3)
//		let h0 = Float(2)
//		for j_phi in 0..<dim {
//			var iStop:Int?
//			var rhoCutted:Float?
//			var dH = Float(0)
//			var dL = Float(0)
//			for i_theta in (1..<dim-1).reversed() {
//				let r0 = calcCoords(i_theta - 1, j_phi, &table)
//				let r1 = calcCoords(i_theta, j_phi, &table)
//				let dr = deriv(r0, r1)
//				if dr.rho < dr.h {
//					dH += dr.h
//					if dH > h0 {
//						break
//					}
//				} else {
//					dL += dr.rho
//					rhoCutted = table[i_theta][j_phi]
//					iStop = i_theta
////					if dL > k0*dH {
////						dH = 0
////					}
//				}
//			}
//			if let thetaFloor = iStop,
//			  let rho = rhoCutted {
//			   for i_theta in thetaFloor..<dim {
//				   table[i_theta][j_phi] = rho
//			   }
//			}
//
//		}
//
//	}
	
	// вначале записывает контуры, затем в конце итоговую сетку
//	private func truncateTheFloor() -> [[Float3]] {
//
//		var res:[[Float3]] = []		// содержит и контуры и обрезанную сетку
//		var perimeters:[(height:Float, value:Float)] = []
//		let d:Float = 1
//		let nLayers = 20
//		for n in 0..<nLayers {
//			let layerHeight = d*Float(n)
//			if let loop = calcCurveLoop(layerHeight) {
//				let perimeter = calcPerimeter(loop)
//				if perimeter > 0 {
//					perimeters.append((height: layerHeight, value: perimeter))
//					res.append(loop)
//				}
//
//			}
//		}
//
//		layersNumber = res.count
//
//
//		(thisLayer, cutHeight) = checkPerimeter(perimeters)
//
//
//		var mesh:[Float3] = []
//		for i in 0..<dim {	// theta
//			for j in 0..<dim { // phi
//				let pos = calcCoords(i, j, &table)
//				mesh.append(pos)
//			}
//		}
//		mesh.removeAll(where: {$0.z < cutHeight})
//		res.append(mesh)
//		return res
//	}
	
//	private func calcCurveLoop(_ cutHeight:Float ) -> [Float3]? {
//		var points: [Float3] = []	// without z coords only x and y
//		for nPhi in 0..<dim {	// theta
//			var dMin:Float = 5
//			var closestPoint:Float3?
//			for nTheta in 0..<dim { // phi
//				let pos = calcCoords(nTheta, nPhi, &table)
//				if dot(pos, pos) > Float(0) {
//					let dH = abs(pos.z - cutHeight)
//					if dH < dMin {
//						dMin = dH
//						closestPoint = pos
//					}
//				}
//			}
//			if let p = closestPoint {
//				points.append(p)
//			}
//		}
//		if !points.isEmpty {
//			points.append(points[0]) // close in loop
//			return points
//		} else {
//			return nil
//		}
//	}
//
//	private func calcPerimeter(_ points:[Float3]) -> Float {
//		var res:Float = 0
//
//		for i in 0..<points.count-1 { // calc perimeter
//			let dr = points[i] - points[i+1]
//			res += sqrt(dot(dr, dr))
//		}
//		return res
//	}
	
	private func checkPerimeter ( _ perimeters: [(height:Float, value:Float)] ) -> (layer:Int, height:Float) {

		var maxPer:Float = 0
		var n = 0
		for i in 0..<perimeters.count {
			let value = perimeters[i].value
			if value > maxPer {
				maxPer = value
				n = i
			}
		}
		
		var ddPMax:Float = 0
		for i in n+2..<perimeters.count-4 {
			let ddp = perimeters[i+2].value + perimeters[i-2].value + perimeters[i+1].value + perimeters[i-1].value - 4*perimeters[i].value
			if ddp > ddPMax {
				n = i
				ddPMax = ddp
			}
		}
		return (n+2, perimeters[n+2].height)

//		var minPer:Float = 1e6
//		var iMin = 0
//		for i in iMax..<perimeters.count {
//			if perimeters[i].value < minPer {
//				minPer = perimeters[i].value
//				iMin = i
//			}
//		}
//		return (iMin, perimeters[iMin].height)

	}
	
//	private func writeNodes() -> String {
//		var res:String = ""
//		for i in 0..<dim {
//			for j in 0..<dim {
//				var str = ""
//				if table[i][j] != Float() {
//					let pos = calcCoords(i, j, &table)
//					str = "v \(pos.x) \(pos.y) \(pos.z)\n"
//				} else {
//					if (renderer.currentState != .separate) {
//						str = "v 0 0 0\n"
//					}
//				}
//				res.append(str)
//			}
//		}
//
//		if (renderer.currentState != .separate) {
//			for i in 0..<dim {
//				for j in 0..<dim {
//					if (table[i][j] != Float()) {
//						if (j+1 != dim && table[i][j+1] != Float()) {
//							let index = i*dim + j
//							res.append("l \(index+1) \(index+2)\n")
//						}
//						if (i+1 != dim && table[i+1][j] != Float()) {
//							let index = (i+1)*dim + j
//							res.append("l \(index-dim+1) \(index+1)\n")
//						}
//					}
//				}
//			}
//		}
//
//		return res
//	}
	
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
