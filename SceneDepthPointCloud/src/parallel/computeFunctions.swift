import MetalKit

extension Renderer {
	
	public func startHeightCorrection() {
				
		guard let commandBuffer = commandQueue.makeCommandBuffer(),
			  let commandEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
		let grid = curveGridBuffer.buffer
		commandEncoder.setComputePipelineState(heightCorrectionState)
		
		commandEncoder.setBuffer(grid)
		commandEncoder.setBytes(&currentViewSector, length: MemoryLayout<ViewSector>.stride, index: Int(kViewSector.rawValue))
		
		guard let sector = currentViewSector else { return }
		var shiftOfFloor = floorShifts[Int(sector.number)]
		commandEncoder.setBytes(&shiftOfFloor, length: MemoryLayout<Float>.stride, index: Int(kFloorShift.rawValue))
		
		let nTotal = MTLSize(width: grid.count, height: 1, depth: 1)
		let w = MTLSize(width: segmentationState.maxTotalThreadsPerThreadgroup, height: 1, depth: 1)
		commandEncoder.dispatchThreads(nTotal, threadsPerThreadgroup: w)
		
		commandEncoder.endEncoding()
		commandBuffer.commit()
		
		commandBuffer.waitUntilCompleted()

	}
	
	
	public func startSegmentation() {
                
		guard let commandBuffer = commandQueue.makeCommandBuffer(),
			  let commandEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
		let grid = curveGridBuffer.buffer
		let pointsBuffer = curveGridBuffer.borderPoints
		commandEncoder.setComputePipelineState(segmentationState)
		
		commandEncoder.setBuffer(grid)
//		commandEncoder.setBytes(&pointCloudUniforms, length: MemoryLayout<CoordData>.stride, index: Int(kPointCloudUniforms.rawValue))
		
//		var p:Float3 = footMetric.heightInRise.mean // передаём координату поиска для определения зоны подъёма (требуются только (x,y) для пересчёта координаты z)
//		commandEncoder.setBytes(&p, length: MemoryLayout<Float3>.stride, index: Int(kRisePoint.rawValue))
//		commandEncoder.setBuffer(pointsBuffer)
		
		let nTotal = MTLSize(width: grid.count, height: 1, depth: 1)
		let w = MTLSize(width: segmentationState.maxTotalThreadsPerThreadgroup, height: 1, depth: 1)
		commandEncoder.dispatchThreads(nTotal, threadsPerThreadgroup: w)
		
		commandEncoder.endEncoding()
		commandBuffer.commit()
		
		commandBuffer.waitUntilCompleted()

    }
	
	public func reductBorderPoints() {
		guard let commandBuffer = commandQueue.makeCommandBuffer(),
			  let commandEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
		let border = curveGridBuffer.borderPoints
		commandEncoder.setComputePipelineState(reductionBorderState)
		commandEncoder.setBuffer(border)
		
		let nTotal = MTLSize(width: border.count, height: 1, depth: 1)
		let w = MTLSize(width: reductionBorderState.maxTotalThreadsPerThreadgroup, height: 1, depth: 1)
		commandEncoder.dispatchThreads(nTotal, threadsPerThreadgroup: w)
		
		commandEncoder.endEncoding()
		commandBuffer.commit()
		
		commandBuffer.waitUntilCompleted()
		
	}
	
	
	func convertToMm(cm length:Float) -> Float {
		return round(1000*length)
	}
	
	func anglePos(alpha: Float) -> Int {
		let dAlpha = 2*Float.pi / Float(PHI_GRID_NODE_COUNT)
		return Int(alpha/dAlpha)
	}
	
	// вычисление базиса в зависимости от текущей точки носка при измерении пучков и точки пятки при измерении длины
	func calcFootBasis() {
		let toePoint = footMetric.bunchWidth.c.mean
		let heelPoint = footMetric.length.b.mean
		var lVec = (heelPoint - toePoint)
		lVec.z = 0
		let e1 = normalize(lVec);
		let e2 = simd_float3(-e1.y, e1.x, 0)
		
		print("\(e1.x) \(e1.y)")
		
		footMetric.basis = (el:e1, en:e2)
	}
	
	// координаты точки в базисе ноги (координату z возвращаем неизменной)
	func convertToFootBasis(_ p:Float3) -> Float3 {
		let x = dot(p, footMetric.basis.el)
		let y = dot(p, footMetric.basis.en)
		let z = p.z
		return simd_float3(x,y,z)
	}
	
	// возвращает точку на оси ноги ( 0 <= percent <= 1)
	func findPointOnFootAxis(_ percent:Float) -> Float3 {
		let toePoint = footMetric.bunchWidth.c.mean
		let heelPoint = footMetric.length.b.mean
		let dL = toePoint - heelPoint
		
		return heelPoint + percent*dL
	}
	
	// percent from (toe) to (heel) -> (out, inner)
	// isOuter marks outer point
	func pickWidthPoint(_ buffer: inout MetalBuffer<BorderPoints>) {
		
		// rCoord - в исходном базисе
		// Точка ищется линейным перебором. TODO переделать под метод деления пополам при больших массивах!
		func findInterval(_ rCoord:Float3, _ range:(iStart:Int, iEnd:Int)) -> Int? {
			let x0 = convertToFootBasis(rCoord).x
			for i in range.iStart..<range.iEnd {
				let p0 = convertToFootBasis(buffer[i].mean)
				let p1 = convertToFootBasis(buffer[i+1].mean)
				if (p0.x-x0)*(p1.x-x0) < 0 {
					return i
				}
			}
			return nil
		}
		
//		// Метод деления пополам (проверить!)
//		func findInterval(_ rCoord:Float3, _ range:(a:Int, b:Int)) -> Int? {
//
//			if ( convertToFootBasis(buffer[range.a].mean).x*convertToFootBasis(buffer[range.b].mean).x >= 0) {
//				return nil
//			}
//			var delta:(a:Int,b:Int) = range
//			while ( delta.b - delta.a > 1 ) {
//				let p0 = convertToFootBasis(buffer[delta.a].mean)
//				let i = (delta.a + delta.b) / 2
//				let pi = convertToFootBasis(buffer[i].mean)
//
//				if ( p0.x*pi.x < 0 ) {
//					delta.b = i
//				} else {
//					delta.a = i
//				}
//			}
//			return delta.a
//		}
		
		// find toe point
		let interval = (a: anglePos(alpha: Float(11)/Float(12)*Float.pi),
						   b: anglePos(alpha: Float(13)/Float(12)*Float.pi))
		let pickedPointIndex = findIndexOfFarthestDistance(buffer: buffer, interval: interval, isToe: true)

		footMetric.bunchWidth.c.mean = buffer[pickedPointIndex].mean	// update the toe point
		
		calcFootBasis()
		
		let percent:(from:Float,to:Float) = (metricMode == .bunchWidthOuter) ? (from: 0.85,to:0.55): (from: 0.9,to:0.6)
		
		let pPercent0 = findPointOnFootAxis(percent.from)
		let pPercent1 = findPointOnFootAxis(percent.to)
		
		// в зависимости от состояния
		let searchInterval:(Int,Int) = (metricMode == .bunchWidthOuter) ? (0, pickedPointIndex)
			: (pickedPointIndex, buffer.count)
		
		let iStart:Int! = findInterval(pPercent0, searchInterval)
		let iEnd:Int! = findInterval(pPercent1, searchInterval)
		
		if (iStart != nil && iEnd != nil) {
			// update interval
			footMetric.interval.a.mean = buffer[iStart].mean
			footMetric.interval.b.mean = buffer[iEnd].mean
			
			var maxDistance:Float = 0
			var p:Float3!
			for i in min(iStart,iEnd)..<max(iStart,iEnd) {
				let distanceToLine = abs(convertToFootBasis(buffer[i].mean - footMetric.bunchWidth.c.mean).y)
				if ( distanceToLine > maxDistance ) {
					maxDistance = distanceToLine
					p = buffer[i].mean
				}
			}
			
			if p != nil {
				if metricMode == .bunchWidthOuter {
					footMetric.bunchWidth.a.mean = p
					currentMeasured = footMetric.bunchWidth.a.mean.y
					print("!!!!! bunch width OUTER !!!!")
				} else {
					footMetric.bunchWidth.b.mean = p
					currentMeasured = footMetric.bunchWidth.b.mean.y
					print("!!!!! bunch width INNER !!!!")
				}
				
			}

		}
	}
	
	public func pickLengthPoint(_ buffer: inout MetalBuffer<BorderPoints>) {
		
		var pickedPointIndex:Int
		let interval:(a:Int,b:Int)
		if metricMode == .lengthToe {
			interval = (a: anglePos(alpha: Float(11)/Float(12)*Float.pi),
							   b: anglePos(alpha: Float(13)/Float(12)*Float.pi))
			pickedPointIndex = findIndexOfFarthestDistance(buffer: buffer, interval: interval, isToe: true)
			
		} else {
			interval = (a: anglePos(alpha: 0.5*Float.pi),
								b: anglePos(alpha: 1.5*Float.pi))
			pickedPointIndex = findIndexOfFarthestDistance(buffer: buffer, interval: interval, isToe: false)

		}
		// update interval
		footMetric.interval.a.mean = buffer[interval.a].mean
		footMetric.interval.b.mean = buffer[interval.b].mean
	
		let pp = buffer[pickedPointIndex].mean
		
		if metricMode == .lengthToe {
			footMetric.length.a.mean = pp
			currentMeasured = footMetric.length.a.mean.x
		} else if metricMode == .lengthHeel {
			footMetric.length.b.mean = pp
			currentMeasured = footMetric.length.b.mean.x
		}
		
	}
	
	func pickHeightInRise(_ buffer: inout MetalBuffer<BorderPoints>) {
		let interval = (a: anglePos(alpha: Float(11)/Float(12)*Float.pi),
						   b: anglePos(alpha: Float(13)/Float(12)*Float.pi))
		let pickedPointIndex = findIndexOfFarthestDistance(buffer: buffer, interval: interval, isToe: true)
		footMetric.bunchWidth.c.mean = buffer[pickedPointIndex].mean	// update the toe point
		
		var pHR = findPointOnFootAxis(0.5)	//  берём только (x,y)-координаты
		let p = buffer[Int(PHI_GRID_NODE_COUNT + 9)].mean	// координата z берётся из значений посчитанных в шейдере processSegmentation
		
		
		let c0 = buffer[0]
		let ch = buffer[Int(PHI_GRID_NODE_COUNT + 9)]
		
		let arr0 = buffer[0].coords
		let arrh = buffer[Int(PHI_GRID_NODE_COUNT+9)].coords
		
		
		print("----- \(arrh)")
		
		pHR.z = arrh.4.z
		footMetric.heightInRise.mean = pHR	// определяем координату зоны подъёма, также необходимую для постоянного перерасчёта в шейдере
		currentMeasured = footMetric.heightInRise.mean.z
	}
	
	func updateCenterAndcamProjection() {
		let mat = pointCloudUniforms.localToWorld;
		let camPos = mat*simd_float4(0, 0, 0, 1);
		let toLocalCS = float4x4( simd_float4( 1, 0, 0, 0),
								  simd_float4( 0, 0, 1, 0),
								  simd_float4( 0, 1, 0, 0),
								  simd_float4( 0, 0, -pointCloudUniforms.floorHeight, 1)
		)
		let cp = toLocalCS*camPos
		camPosition = simd_float3(cp.x, cp.y, cp.z)
	}
	
	func updateAllNodes() {
		guard let commandBuffer = commandQueue.makeCommandBuffer(),
			  let commandEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
		let buffer = curveGridBuffer.buffer
		commandEncoder.setComputePipelineState(equalFramePerNodeState)
		commandEncoder.setBuffer(buffer)
		commandEncoder.setBytes(&frameAccumulated, length: MemoryLayout<Int>.stride, index: 0)
		
		commandEncoder.setBytes(&currentViewSector, length: MemoryLayout<ViewSector>.stride, index: Int(kViewSector.rawValue))
		
		
		let nTotal = MTLSize(width: buffer.count, height: 1, depth: 1)
		let w = MTLSize(width: equalFramePerNodeState.maxTotalThreadsPerThreadgroup, height: 1, depth: 1)
		commandEncoder.dispatchThreads(nTotal, threadsPerThreadgroup: w)
		
		commandEncoder.endEncoding()
		commandBuffer.commit()
		
		commandBuffer.waitUntilCompleted()
	}
	

	
	public func calcFloorShifts() {
		
		let columnCount = Int(PHI_GRID_NODE_COUNT)
		let halfRowCount = Int(U_GRID_NODE_COUNT)
		let halfTableIndex = columnCount*halfRowCount
		
		let hl:Float = Float(BOX_HALF_LENGTH)
		let hw:Float = Float(BOX_HALF_WIDTH)
		let shiftsCS = [
			   simd_float3(-hl, -hw, 0),
			   simd_float3(  0, -hw, 0),
			   simd_float3( hl, -hw, 0),
			   simd_float3( hl,  hw, 0),
			   simd_float3(  0,  hw, 0),
			   simd_float3(-hl,  hw, 0)
		   ]
		
			
		// tableRow must less than halfRowCount!
		func getIndecesRangeFromSectorNumber(tableRow:Int, sector:Int) -> (iStart:Int, iEnd:Int) {
			var n:Int = 0
			var width:Int
			let start:Int
			switch sector {
			case 0,2,3,5:
				if sector == 0 {
					n = sector
				} else if (sector == 2 || sector == 3) {
					n = sector - 1
				} else if (sector == 5) {
					n = sector - 2
				}
				width = columnCount/4
				start = tableRow*columnCount
			case 1,4:
				if sector == 1 {
					n = 0
				} else {
					n = 1
				}
				width = columnCount/2
				start = halfTableIndex + tableRow*columnCount
			default:
				return (iStart:0, iEnd:0)
			}
			
			
			let i0 = start + n*width
			let iN = i0 + width
			return (iStart:i0, iEnd:iN)
		}
		
		func calcBufferValue(index:Int) -> (sector:Int,value:Float3?) {

			let dPhi:Float = 2*Float.pi / Float(columnCount)
			let dV:Float = Float(U_STEP)
			let grid = curveGridBuffer.buffer

			let i = index / columnCount
			let j = index % columnCount
			let u_coord = grid[index].mean

			let k:Float = 1
			let h0:Float = -0.03

			let isSecondTable = i > halfRowCount

			let iShift = isSecondTable ? Int(U_GRID_NODE_COUNT) : 0;

			let v_coord = Float(i - iShift)*dV;

			let uv_sqrt = sqrt(k*k*v_coord*v_coord + u_coord*u_coord);
			let rho = sqrt(0.5*(u_coord + uv_sqrt)) / k;
			let h = sqrt(k*k*rho*rho - u_coord) + h0;

			let phi = Float(j)*dPhi

			// detect sector
			var secNum:Int = -1
			if isSecondTable {
				if ( (Float.pi <= phi) && (phi < 2*Float.pi) ) { 	// понять и простить
					secNum = 4
				} else {
					secNum = 1
				}
			} else {
				if ( (Float.pi < phi) && (phi < 1.5*Float.pi - dPhi) ) {	// понять и простить
					secNum = 3
				} else if ( (1.5*Float.pi < phi) && (phi < 2*Float.pi) ) {
					secNum = 5
				} else if ( (0 < phi) && (phi < 0.5*Float.pi) ) {
					secNum = 0
				} else if ( (0.5*Float.pi < phi) && (phi < Float.pi) ) {
					secNum = 2
				}

			}

			if u_coord == 0 || secNum == -1 {
//				if 200 <= index && index < 250 {
//					print("0 sector")
//				}
				print("\(u_coord) & \(secNum)")
				return (sector:secNum, value: nil)
			} else {

//				if 200 < index && index < 250 {
//					print("0 sector")
//				}

				let pos = Float3(rho*cos(phi), rho*sin(phi), h) + shiftsCS[secNum]
//				print("*** r:\(pos) phi:\(phi)(\(Float.pi)) ")
				return (sector:secNum, value:pos)
			}


		}
			
		func playRandomIndex(sector:Int) -> Int {
//			let row = Int.random(in: 0..<halfRowCount/10)
			let row = Int.random(in: 1..<10)
			let colRange = getIndecesRangeFromSectorNumber(tableRow: row, sector: sector)
			print("ROW: \(row) indexRange: \(colRange.iStart) \(colRange.iEnd)")
			let index = Int.random(in: colRange.iStart..<colRange.iEnd)
			return index
		}
			
		guard let sector = currentViewSector?.number else {
			print("No sector")
			return
		}
			
//		let range = getIndecesRangeFromSectorNumber(tableRow: 3, sector: Int(sector))
		
		var heights:(count:Int, totalValue:Float) = (count:0, totalValue:0)
		let randomCount = 10
		for _ in 0..<randomCount {
			let index = playRandomIndex(sector: Int(sector))
			
			print("index: \(index)")
			
			let res = calcBufferValue(index: index)
			print(res.value)
			guard let coord = res.value else { continue }
			if (res.sector == sector) { // лишняя проверка не помешает
				if abs(coord.z) < 0.003 {
					curveGridBuffer.buffer[index].group = FloorMarker
					heights.totalValue += coord.z
					heights.count += 1
				}
			}
		}

//		runThroughIndeces(i0: columnCount, iN: 3*columnCount)	//
//		runThroughIndeces(i0: halfTableIndex + columnCount, iN: halfTableIndex + 2*columnCount)

		if (heights.count > 2*randomCount/3) {
			let deltaFloor = heights.totalValue / Float(heights.count)
			floorShifts[Int(sector)] = deltaFloor
		}
		
		
		
//		print("0: \(1000*floorShifts[0]) | 1: \(1000*floorShifts[1]) | 2: \(1000*floorShifts[2]) | 3: \(1000*floorShifts[3]) | 4: \(1000*floorShifts[4]) | 5: \(1000*floorShifts[5])")
	}

}
