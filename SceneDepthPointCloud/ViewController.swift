/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the AR experience.
*/

import UIKit
import Metal
import MetalKit
import ARKit

final class ViewController: UIViewController, ARSessionDelegate {
    private let isUIEnabled = true
    private let sendButton = UIButton(frame: CGRect(x: 100, y:100, width: 100, height: 50));
    private let startButton = UIButton(frame: CGRect(x: 100, y:100, width: 100, height: 50));
    private var stackView: UIStackView!

    private let session = ARSession()
    private var renderer: Renderer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sendButton.backgroundColor = .orange
        sendButton.setTitle("Отправить", for: .normal)
        sendButton.addTarget(self, action: #selector(sendAction), for: .touchUpInside)
        
        startButton.backgroundColor = .green
        startButton.setTitle("Начать сканирование", for: .normal)
        startButton.addTarget(self, action: #selector(startAction), for: .touchUpInside)
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }
        
//        let orientation = UIDevice.current.orientation.isLandscape
        
        session.delegate = self
        
        // Set the view to use the default device
        if let view = view as? MTKView {
            view.device = device
            
            view.backgroundColor = UIColor.clear
            // we need this to enable depth test
            view.depthStencilPixelFormat = .depth32Float
            view.contentScaleFactor = 1
            view.delegate = self
            
            // Configure the renderer to draw to the view
            renderer = Renderer(session: session, metalDevice: device, renderDestination: view)
            renderer.drawRectResized(size: view.bounds.size)
        }
        
        stackView = UIStackView(arrangedSubviews: [startButton, sendButton])
        sendButton.isHidden = true
        stackView.isHidden = !isUIEnabled
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 20
        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -50)
        ])
//        NotificationCenter.default.addObserver(self, selector: #selector(rotated), name: UIDevice.orientationDidChangeNotification, object: nil)
    }
    
    @objc
    func sendAction(_ sender: UIButton!) {
        
        print("SEND!!!")
        
//        smooth()
        renderer.separate()
        
        
        let data = separateData()
        let objects = convertToObj(separated: data)
//        let objects = exportToObjFormat()
        
        
        let fNames = [
//            Int(Unknown.rawValue): "Unknown",
//                                  Int(Floor.rawValue): "Floor",
//                                  Int(Foot.rawValue): "Foot"
            Int(Up.rawValue): "Up",
            Int(Front.rawValue): "Front",
            Int(Back.rawValue): "Back",
            Int(Left.rawValue): "Left",
            Int(Right.rawValue): "Right"
        ]
        
        var urls:[URL] = []
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            for (id, str) in objects {
//                if id == Int(Unknown.rawValue) { continue }
                let fileName = fNames[id]! + ".obj"
                let url = dir.appendingPathComponent(fileName)
                urls.append(url)
                do {
                    try str.write(to: url, atomically: true, encoding: String.Encoding.utf8)
                }
                catch {
                    print("Error!")
                }
                
            }
            
            let activity = UIActivityViewController(activityItems: urls, applicationActivities: .none)
            activity.isModalInPresentation = true
            present(activity, animated: true, completion: nil)
        }
        
        
        renderer.setState(state: .findFootArea)
        sendButton.isHidden = true
        startButton.isHidden = !sendButton.isHidden
    }
    
    
    @objc
    func startAction(_ sender: UIButton!) {
        
        print("START!!!")
        
        renderer.setState(state: .scanning)
        renderer.initializeNodeBuffer(view: Up)
        renderer.initializeNodeBuffer(view: Front)
        renderer.initializeNodeBuffer(view: Back)
        renderer.initializeNodeBuffer(view: Left)
        renderer.initializeNodeBuffer(view: Right)
        renderer.frameAccumulated = 0
        sendButton.isHidden = false
        startButton.isHidden = !sendButton.isHidden
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a world-tracking configuration, and
        // enable the scene depth frame-semantic.
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = .sceneDepth

        // Run the view's session
        session.run(configuration)
        
        // The screen shouldn't dim during AR experiences.
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    // Auto-hide the home indicator to maximize immersion in AR experiences.
    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }
    
    // Hide the status bar to maximize immersion in AR experiences.
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user.
        guard error is ARError else { return }
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        DispatchQueue.main.async {
            // Present an alert informing about the error that has occurred.
            let alertController = UIAlertController(title: "The AR session failed.", message: errorMessage, preferredStyle: .alert)
            let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
                alertController.dismiss(animated: true, completion: nil)
                if let configuration = self.session.configuration {
                    self.session.run(configuration, options: .resetSceneReconstruction)
                }
            }
            alertController.addAction(restartAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    
    func separateData() -> [Int:[(Int,Int,Float)]] {
        var res = [
//            Int(Unknown.rawValue):[(Int,Int,Float)](),
//                    Int(Foot.rawValue):[(Int,Int,Float)](),
//                    Int(Floor.rawValue):[(Int,Int,Float)]()
            Int(Up.rawValue): [(Int,Int,Float)](),
            Int(Front.rawValue): [(Int,Int,Float)](),
            Int(Back.rawValue): [(Int,Int,Float)](),
            Int(Left.rawValue): [(Int,Int,Float)](),
            Int(Right.rawValue): [(Int,Int,Float)](),
        ]
        
        for i in 0..<renderer.upBuffer.count {
            let node = renderer.upBuffer[i]
//            if node.complete != 1 {
//                continue
//            }
            let row = Int( gridRow(Int32(i), Int32(GRID_NODE_COUNT)) )
            let col = Int( gridColumn(Int32(i), Int32(GRID_NODE_COUNT)) )
            let val = getMedian(node)
//            res[Int(node.group.rawValue)]!.append( (row, col, val) )
            res[Int(Up.rawValue)]!.append( (row, col, val) )
        }
        
        for i in 0..<renderer.frontBuffer.count {
            let node = renderer.frontBuffer[i]
//            if node.complete != 1 {
//                continue
//            }
            let row = Int( gridRow(Int32(i), Int32(GRID_NODE_COUNT/2)) )
            let col = Int( gridColumn(Int32(i), Int32(GRID_NODE_COUNT/2)) )
            let val = getMedian(node)
//            res[Int(node.group.rawValue)]!.append( (row, col, val) )
            res[Int(Front.rawValue)]!.append( (row, col, val) )
        }
        
        for i in 0..<renderer.backBuffer.count {
            let node = renderer.backBuffer[i]
//            if node.complete != 1 {
//                continue
//            }
            let row = Int( gridRow(Int32(i), Int32(GRID_NODE_COUNT/2)) )
            let col = Int( gridColumn(Int32(i), Int32(GRID_NODE_COUNT/2)) )
            let val = getMedian(node)
//            res[Int(node.group.rawValue)]!.append( (row, col, val) )
            res[Int(Back.rawValue)]!.append( (row, col, val) )
        }
        
        for i in 0..<renderer.leftBuffer.count {
            let node = renderer.leftBuffer[i]
//            if node.complete != 1 {
//                continue
//            }
            let row = Int( gridRow(Int32(i), Int32(GRID_NODE_COUNT)) )
            let col = Int( gridColumn(Int32(i), Int32(GRID_NODE_COUNT)) )
            let val = getMedian(node)
//            res[Int(node.group.rawValue)]!.append( (row, col, val) )
            res[Int(Left.rawValue)]!.append( (row, col, val) )
        }
        
        for i in 0..<renderer.rightBuffer.count {
            let node = renderer.rightBuffer[i]
//            if node.complete != 1 {
//                continue
//            }
            let row = Int( gridRow(Int32(i), Int32(GRID_NODE_COUNT)) )
            let col = Int( gridColumn(Int32(i), Int32(GRID_NODE_COUNT)) )
            let val = getMedian(node)
//            res[Int(node.group.rawValue)]!.append( (row, col, val) )
            res[Int(Right.rawValue)]!.append( (row, col, val) )
        }
        return res
        
    }
    
    
    func convertToObj(separated data:[Int:[(Int,Int,Float)]]) -> [Int:String] {
        
        func writeEdges(projection:Int, input data: [(Int,Int,Float)]) -> String {
            
            func fullTable(_ data:[(Int,Int,Float)], iDim:Int, jDim:Int) -> [[Float]] {
                var res = Array(repeating:Array(repeating: Float(), count: jDim), count: iDim)
                for ( i, j, val ) in data {
                    res[i][j] = val
                }
                return res
            }
            
            var res = ""
           
            
            var iDim = Int(GRID_NODE_COUNT)
            let radius = Float(RADIUS)
            let gridNodeDistance = Float(2)*radius / Float(GRID_NODE_COUNT)
            var jDim = iDim
            if projection == Left.rawValue || projection == Right.rawValue {
                iDim /= 2
            } else if projection == Front.rawValue || projection == Back.rawValue {
                jDim /= 2
            }
            
            let table = fullTable(data, iDim:iDim, jDim:jDim)
            for i in 0..<iDim {
                for j in 0..<jDim {
                    var str = ""
                    if table[i][j] != Float() {
                        if projection == Up.rawValue {
                            str = "v \(1000.0*(Float(i)*gridNodeDistance - radius)) \(1000.0*(Float(j)*gridNodeDistance - radius)) \(1000.0*table[i][j])\n"
                        } else if projection == Front.rawValue || projection == Back.rawValue {
                            str = "v \(1000.0*(Float(i)*gridNodeDistance - radius)) \(1000.0*table[i][j]) \(1000.0*Float(j)*gridNodeDistance)\n"
                        } else if projection == Left.rawValue || projection == Right.rawValue {
                            str = "v \(1000.0*table[i][j]) \(1000.0*(Float(j)*gridNodeDistance - radius)) \(1000.0*Float(i)*gridNodeDistance)\n"
                        } else {}
                    } else {
                        str = "v 0 0 0\n"
                    }
                    res.append(str)
                }
            }
            
            for i in 0..<iDim {
                for j in 0..<jDim {
                    if (table[i][j] != Float()) {
                        if (j+1 != jDim && table[i][j+1] != Float()) {
                            let index = i*jDim + j
                            res.append("l \(index+1) \(index+2)\n")
                        }
                        if (i+1 != iDim && table[i+1][j] != Float()) {
                            let index = (i+1)*jDim + j
                            res.append("l \(index-jDim+1) \(index+1)\n")
                        }
                    }
                }
            }
            
            return res
        }
        
        
        var res = [Int:String]()
        for (key, val) in data {
            res[key] = writeEdges(projection: key, input: val)
        }
        return res
        
    }


}

// MARK: - MTKViewDelegate

extension ViewController: MTKViewDelegate {
    // Called whenever view changes orientation or layout is changed
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        renderer.drawRectResized(size: size)
    }
    
    // Called whenever the view needs to render
    func draw(in view: MTKView) {
        renderer.draw()
    }
    func share(url: URL) {
        let docContr = UIDocumentInteractionController(url: url)
        docContr.uti = "public.data, public.content"
        docContr.name = url.lastPathComponent
        docContr.presentPreview(animated: true)
        
    }

}

// MARK: - RenderDestinationProvider

protocol RenderDestinationProvider {
    var currentRenderPassDescriptor: MTLRenderPassDescriptor? { get }
    var currentDrawable: CAMetalDrawable? { get }
    var colorPixelFormat: MTLPixelFormat { get set }
    var depthStencilPixelFormat: MTLPixelFormat { get set }
    var sampleCount: Int { get set }
}

extension MTKView: RenderDestinationProvider {
    
}
