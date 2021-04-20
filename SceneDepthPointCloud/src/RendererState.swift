enum RendererState: Int32 {
    case findFootArea = 0, scanning = 1, separate = 2
    
    init() {
        self = .findFootArea
    }
    
    mutating func nextState() {
        switch self {
        case .scanning, .separate:
            self = .findFootArea
        case .findFootArea:
            self = isDebugMode ? .separate: .scanning
        }
    }
}

