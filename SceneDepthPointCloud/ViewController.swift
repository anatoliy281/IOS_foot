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
//    private let colorMeshButton = UIButton(frame: CGRect(x: 100, y:100, width: 100, height: 50));
    
    private let session = ARSession()
    private var renderer: Renderer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sendButton.backgroundColor = .orange
        sendButton.setTitle("Отправить", for: .normal)
        sendButton.addTarget(self, action: #selector(sendAction), for: .touchUpInside)
        
//        colorMeshButton.backgroundColor = .green
//        colorMeshButton.setTitle("Определить пол", for: .normal)
//        colorMeshButton.addTarget(self, action: #selector(colorAction), for: .touchUpInside)
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }
        
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
        
        let stackView = UIStackView(arrangedSubviews: [
            sendButton,
//            colorMeshButton,
//            smoothMeshButton
        ])
        stackView.isHidden = !isUIEnabled
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 20
        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -50)
        ])
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
            Int(Unknown.rawValue): "Unknown",
                                  Int(Floor.rawValue): "Floor",
                                  Int(Foot.rawValue): "Foot"]
        
        var urls:[URL] = []
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            for (id, str) in objects {
                if id == Int(Unknown.rawValue) { continue }
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
    }
    
    
    @objc
    func colorAction(_ sender: UIButton!) {
        
        print("PAINT!!!")
        
        renderer.separate()
        
//        separate()
        
    }
    
    @objc
    func smoothAction(_ sender: UIButton!) {
        
        print("SMOOTH!")
        
       smooth()
        
    }
    
    func smooth() {
        print("smooth data")

        func filterMaskMedian() {
            let dim = Int(GRID_NODE_COUNT)
            var node = renderer.myGridBuffer

            func flatIndex(_ i:Int, _ j:Int) -> Int {
                return i*dim + j
            }

            func calcMedian(_ i:Int, _ j:Int) -> Float {
                let mask = [
                    flatIndex(i, j), flatIndex(i, j+1), flatIndex(i, j+2),
                    flatIndex(i+1, j), flatIndex(i+1, j+1), flatIndex(i+1, j+2),
                    flatIndex(i+2, j), flatIndex(i+2, j+1), flatIndex(i+2, j+2)
                ]
                var vals = mask.map({ getMedian(node[$0]) })
                vals.sort(by: {$0 < $1})
                return vals[mask.count/2]
            }

            for i in 0..<dim-2 {
                for j in 0..<dim-2 {
                    let medianValue = calcMedian(i, j)
                    let medianIndex = flatIndex(i+1, j+1)
                    node[medianIndex].heights.0 = medianValue
                    node[medianIndex].length = 1
                }
            }
        }

        func getFloorHeight() -> Float {
            var heights = [Double]()

            for i in 0..<renderer.myGridBuffer.count {
                let node = renderer.myGridBuffer[i]
                if (node.group == Floor) {
                    heights.append(Double(getMedian(node)))
                }

            }

            var total:Double = 0
            for h in heights {
                total += h
            }
            return Float( total / Double(heights.count) )
        }

        func setUnknownToFloor(_ floorHeight:Float) {
            for i in 0..<renderer.myGridBuffer.count {
                if (renderer.myGridBuffer[i].group == Unknown) {
                    renderer.myGridBuffer[i] = setAll(floorHeight, 1, Floor)
                }
            }
        }

        let floorHeight = getFloorHeight()
        setUnknownToFloor(floorHeight)
        filterMaskMedian()
        renderer.heights.floor = floorHeight
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
            Int(Unknown.rawValue):[(Int,Int,Float)](),
                    Int(Foot.rawValue):[(Int,Int,Float)](),
                    Int(Floor.rawValue):[(Int,Int,Float)]() ]
        
        for i in 0..<renderer.myGridBuffer.count {
            let node = renderer.myGridBuffer[i]
            let row = Int(gridRow(Int32(i)))
            let col = Int(gridColumn(Int32(i)))
            let val = getMedian(node)
            
            res[Int(node.group.rawValue)]!.append( (row, col, val) )
        }
        
        return res
        
    }
    
    
    func convertToObj(separated data:[Int:[(Int,Int,Float)]]) -> [Int:String] {
        
        func writeEdges(input data: [(Int,Int,Float)]) -> String {
            
            let dim = Int(GRID_NODE_COUNT)
            
            func fullTable(_ data:[(Int,Int,Float)]) -> [[Float]] {
                var res = Array(repeating:Array(repeating: Float(), count: dim), count: dim)
                for ( i, j, val ) in data {
                    res[i][j] = val
                }
                return res
            }
            
            var res = ""
            let table = fullTable(data)
            for i in 0..<dim {
                for j in 0..<dim {
                    var str = ""
                    if table[i][j] != Float() {
                        str = "v \(1000*toCoordinate(Int32(i))) \(1000*toCoordinate(Int32(j))) \(1000*table[i][j])\n"
                    } else {
                        str = "v 0 0 0\n"
                    }
                    res.append(str)
                }
            }
            
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
            
            return res
        }
        
        
        var res = [Int:String]()
        for (key, val) in data {
            res[key] = writeEdges(input: val)
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
