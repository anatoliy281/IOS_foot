// 	   	   TOE
// 	     	|
//			|
// (Y) <----------
//			|
//			|
//			V
//		   (X) HILL
//  	Строим полином 3-ей степени как линию регрессии
//  по заданным точкам float3 буфера buffer из диапазона [a, b) interval
//	Возвращает индекс узла буфера для которой значение в данном узле явл. ближайшим к точке экстремума,
//  а также величину квадрата отклонения между точкой экстремума и значением в данном узле

enum Projection {
	case XY, YX, YZ
}

func extractComponents(_ p:simd_float3, _ projection: Projection) -> (t:Float, f:Float) {
	switch projection {
	case .YX:
		return (p.y, p.x)
	case .XY:
		return (p.x, p.y)
	case .YZ:
		return (p.y, p.z)
	}
}

func extactPoints(buffer:MetalBuffer<BorderPoints>,
				  interval:(a:Int, b:Int),
				  clockwise: Bool = true,
				  projection:Projection) -> [(t:Float,f:Float)] {
	var res = [(Float,Float)]()
	if clockwise {
		for i in interval.a..<interval.b {
			let coord = buffer[i].mean
			let p = extractComponents(coord, projection)
			res.append(p)
		}
	} else {
		let pointCount = buffer.count
		for i in interval.b..<pointCount {
			let coord = buffer[i].mean
			let p = extractComponents(coord, projection)
			res.append(p)
		}
		for i in 0..<interval.a {
			let coord = buffer[i].mean
			let p = extractComponents(coord, projection)
			res.append(p)
		}
		
	}
	
	return res
}

extension String: Error {
	
}

func findQuadraticRegression(points: [(t:Float,f:Float)]) -> simd_float3 {
	
	var M:simd_float3x3 = .init()
	var F:simd_float3 = .init()
	for i in 0..<points.count {
		let f = points[i].f
		let t1 = points[i].t
		let t2 = t1*t1

		F[0] += f; F[1] += f*t1; F[2] += f*t2
		
		M[0,1] += t1;
		M[1,1] += t2;
		M[1,2] += t1*t2;
		M[2,2] += t2*t2
	}
	M[0,0] = Float(points.count)
	M[1,0] = M[0,1]
	M[2,0] = M[1,1]; M[0,2] = M[1,1]
	M[2,1] = M[1,2]
	
	// solve equation mc=f and find c[i]
	let C = simd_mul(M.inverse, F)
	return C
}

func findExtemum(c:simd_float3) -> simd_float2 {
	let tE = -0.5*c[1] / c[2]
	let fE = c[0] + 0.5*tE*c[1]
	return simd_float2(tE, fE)
}

//func closestBufferPoint(_ buffer:MetalBuffer<BorderPoints>,
//						_ p:simd_float2,
//						_ projection:Projection,
//						_ clocwise:Bool = true) -> (i:Int, err:Float) {
//	if clockwise {
//		for i in interval.a..<interval.b {
//			let dist = length_squared( simd_float2(Float(tE-tArr[i]), Float(fE-fArr[i])) )
//			if ( theDist < dist ) {
//				theI = i
//				theDist = dist
//			}
//		}
//	} else {
//		for i in interval.b..<pointCount {
//			let dist = length_squared( simd_float2(Float(tE-tArr[i]), Float(fE-fArr[i])) )
//			if ( theDist < dist ) {
//				theI = i
//				theDist = dist
//			}
//		}
//		for i in 0..<interval.a {
//			let dist = length_squared( simd_float2(Float(tE-tArr[i]), Float(fE-fArr[i])) )
//			if ( theDist < dist ) {
//				theI = i
//				theDist = dist
//			}
//		}
//	}
//}

func findIndexOfFarthestDistance(buffer:MetalBuffer<BorderPoints>,
						 interval:(a:Int, b:Int), isToe: Bool) -> Int {
	
	var index:Int = 0
	if isToe {	// toe extremum
		var dist:Float = 0
		for i in interval.a..<interval.b {
			let distI = length_squared(buffer[i].mean)
			if distI > dist {
				index = i
				dist = distI
			}
		}
	} else { //  find the heel extremum
		var maxX:Float = 0
		let deltaX:Float = 0.002

		for i in interval.b..<buffer.count-1 {
			let xCoord = buffer[i].mean.x
			if xCoord < maxX - deltaX {
				break
			} else if xCoord > maxX {
				index = i
				maxX = xCoord
			}
		}
		
		for i in 0..<interval.a {
			let xCoord = buffer[i].mean.x
			if xCoord < maxX - deltaX {
				break
			} else if xCoord > maxX {
				index = i
				maxX = xCoord
			}
		}
	}
	
	return index
}

//func findHeelToeExtremum(buffer:MetalBuffer<BorderPoints>,
//						 interval:(a:Int, b:Int),
//						 clockwise: Bool = true) -> (i:Int, err:Float) {
//
//	var tArr = [Double]()
//	var fArr = [Double]()
//
//	let pointCount = interval.b - interval.a
//	if (clockwise) {
//		for i in interval.a..<interval.b {
//			let coord = buffer[i].mean
//			tArr.append(Double(coord.y))
//			fArr.append(Double(coord.x))
//		}
//	} else {
//		for i in interval.b..<pointCount {
//			let coord = buffer[i].mean
//			tArr.append(Double(coord.y))
//			fArr.append(Double(coord.x))
//		}
//		for i in 0..<interval.a {
//			let coord = buffer[i].mean
//			tArr.append(Double(coord.y))
//			fArr.append(Double(coord.x))
//		}
//	}
//
//
//	// init matrices
//	var M:simd_double4x4 = .init()
//	var F:simd_double4 = .init()
//	for i in 0..<pointCount {
//		let f = fArr[i]
//		let t1 = tArr[i]
//		let t2 = t1*t1
//
//		F[0] += f; F[1] += f*t1; F[2] += f*t2
//
//		M[0,1] += t1;
//		M[1,1] += t2;
//		M[1,2] += t1*t2;
//		M[2,2] += t2*t2
//	}
//	M[0,0] = Double(pointCount)
//	M[1,0] = M[0,1]
//	M[2,0] = M[1,1]; M[0,2] = M[1,1]
//	M[2,1] = M[1,2]
//
//	// solve equation mc=f and find c[i]
//	let C = simd_mul(M.inverse, F)
//
//	// calc extremum res
//	let tE = -0.5*C[1] / C[2]
//	let fE = C[0] + 0.5*tE*C[1]
//
//	var theDist = Float.greatestFiniteMagnitude
//	var theI = interval.a
//
//	if clockwise {
//		for i in interval.a..<interval.b {
//			let dist = length_squared( simd_float2(Float(tE-tArr[i]), Float(fE-fArr[i])) )
//			if ( theDist < dist ) {
//				theI = i
//				theDist = dist
//			}
//		}
//	} else {
//		for i in interval.b..<pointCount {
//			let dist = length_squared( simd_float2(Float(tE-tArr[i]), Float(fE-fArr[i])) )
//			if ( theDist < dist ) {
//				theI = i
//				theDist = dist
//			}
//		}
//		for i in 0..<interval.a {
//			let dist = length_squared( simd_float2(Float(tE-tArr[i]), Float(fE-fArr[i])) )
//			if ( theDist < dist ) {
//				theI = i
//				theDist = dist
//			}
//		}
//	}
//
//	return (theI, theDist)
//}
