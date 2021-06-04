	
	struct CyclicBuffer {
		
		init(count: Int) {
			maxLen = count
		}
		
		lazy var buffer:[(x:Float, xSq:Float)] = {
			return .init(repeating: (0,0), count: maxLen)
		}()
		
		public let maxLen: Int
		public var curLen: Int = 0
		public var meanValue: Float = 0
		private var meanValueSq: Float = 0
		public var deviation:  Float  {
			sqrt( meanValueSq - meanValue*meanValue )
		}
		
		public mutating func update(_ value: Float) -> Float {
			curLen += 1
			if curLen <= maxLen {
				buffer[curLen-1] = (x: value, xSq: value*value)
				meanValue = (meanValue*Float(curLen - 1) + value ) / Float(curLen)
				meanValueSq = (meanValueSq*Float(curLen - 1) + value*value ) / Float(curLen)
			} else {
				let pos = (curLen - 1)%maxLen
				let oldValue = buffer[pos]
				buffer[pos] = (x:value, xSq:value*value)
				meanValue += (value - oldValue.x) / Float(maxLen)
				meanValueSq +=  (value*value - oldValue.xSq) / Float(maxLen)
			}
			
			return meanValue
		}
		
	}
	
	
