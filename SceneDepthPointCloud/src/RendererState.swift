enum RendererState: Int32 {
	case findFloorPlane = 0, scanning = 1, measuring = 2
    
    init() {
        self = .findFloorPlane
    }
    
    mutating func nextState() {
        switch self {
        case .scanning, .measuring:
            self = .findFloorPlane
        case .findFloorPlane:
            self = isMeasuringMode ? .measuring: .scanning
        }
    }
}

