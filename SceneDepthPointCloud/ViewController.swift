/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the AR experience.
*/

import UIKit
import Metal
import MetalKit
import ARKit
//import "MyMeshData.h"

final class ViewController: UIViewController, ARSessionDelegate {
    private let isUIEnabled = true
    private let sendButton = UIButton(frame: CGRect(x: 100, y:100, width: 100, height: 50));
    private let colorMeshButton = UIButton(frame: CGRect(x: 100, y:100, width: 100, height: 50));
    
    private let session = ARSession()
    private var renderer: Renderer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sendButton.backgroundColor = .green
        sendButton.setTitle("Send!", for: .normal)
        sendButton.addTarget(self, action: #selector(sendAction), for: .touchUpInside)
        
        colorMeshButton.backgroundColor = .green
        colorMeshButton.setTitle("Раскрасить", for: .normal)
        colorMeshButton.addTarget(self, action: #selector(colorAction), for: .touchUpInside)
        
        
//        view.addSubview(sendButton)
//        view.addSubview(colorMeshButton)
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
        
        // RGB Radius control
//        rgbRadiusSlider.minimumValue = 0
//        rgbRadiusSlider.maximumValue = 1.5
//        rgbRadiusSlider.isContinuous = true
//        rgbRadiusSlider.value = renderer.rgbRadius
//        rgbRadiusSlider.addTarget(self, action: #selector(viewValueChanged), for: .valueChanged)
        
        let stackView = UIStackView(arrangedSubviews: [sendButton, colorMeshButton])
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
        
        separate()
        
        
        let data = separateData()
        let objects = convertToObj(separated: data)
//        let objects = exportToObjFormat()
        
        
        let fNames = [Int(Unknown.rawValue): "Unknown",
                                  Int(Floor.rawValue): "Floor",
                                  Int(Foot.rawValue): "Foot"]
        
        var urls:[URL] = []
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            for (id, str) in objects {
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
    
    
    func separate()  {
        let dH:Float = 0.0075
        
        func calcHeightGistro() -> [Float:Int] {
            
            var res = [Float:Int]()
            let grid = renderer.myGridBuffer
            for i in 0..<grid.count {
                let nodeStat = grid[i]
                if nodeStat.length == 0 { continue }
                let h = getMedian(nodeStat)
                let hDescr = floor(h/dH)*dH
                if let cnt = res[hDescr] {
                    res[hDescr] = cnt + 1
                } else {
                    res[hDescr] = 1
                }
            }
            return res
            
        }
        
        
        func findFloor(_ gistro: [Float:Int]) {
            
            var floor = (height: Float(), count:Int())
            for (h, n) in gistro {
                if h != 0 {
                    if (n > floor.count) {
                        floor.height = h
                        floor.count = n
                    }
                }
            }
            
            var grid = renderer.myGridBuffer
            for i in 0..<grid.count {
                var group = Unknown
                if grid[i].length > 0 {
                    let delta = abs( getMedian(grid[i]) - floor.height )
                    group = (delta < dH) ? Floor : Foot
                }
                grid[i].group = group
            }
        }
        
        let gistro = calcHeightGistro()
        
        findFloor( gistro )
    }
    
    @objc
    func colorAction(_ sender: UIButton!) {
        
        print("PAINT!!!")
        
       separate()
        
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
    
    
    func setNullToFloorPoints(_ inMesh: [[SIMD3<Float>]], _ dim:Int, _ dR: Float, _ height: Float) ->[[SIMD3<Float>]] {
        var res = inMesh
        
        for i in 0..<dim {
            for j in 0..<dim {
                if res[i][j] == SIMD3<Float>.zero {
                    let xNode = 1000*indexToPos(i, dim, dR)
                    let zNode = 1000*indexToPos(j, dim, dR)
//                    print(res[i][j])
                    res[i][j].x = xNode
                    res[i][j].y = height
                    res[i][j].z = zNode
//                    print(res[i][j])
//                    print(xNode, height, zNode)
                }
            }
        }
        
        return res
    }
    
    func indexToPos(_ index:Int, _ dim:Int, _ dR:Float) -> Float {
        return (Float(index) - Float(dim/2))*dR
    }
    
    func filterMaskMedian(_ inMesh: [[SIMD3<Float>]], _ dim:Int) -> [[SIMD3<Float>]] {
        var res = inMesh
        
        for i in 1..<dim-1 {
            for j in 1..<dim-1{
                var arr:[SIMD3<Float>] = [ res[i-1][j-1], res[i-1][j], res[i-1][j+1],
                                           res[i][j-1],   res[i][j],   res[i][j+1],
                                           res[i+1][j-1], res[i+1][j], res[i+1][j+1] ]
                arr.sort(by: {
                    $0.y < $1.y
                })
                res[i][j].y = arr[arr.count/2].y
            }
        }
        
        return res
    }
    
    
    func separateData() -> [Int:[(Int,Int,Float)]] {
        var res = [ Int(Unknown.rawValue):[(Int,Int,Float)](),
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
    
    
//    func separate(in slice: [MyMeshData]) -> [Int:[Float?]] {
//        let dim = slice.count
//        var res = [ Int(Unknown.rawValue): Array<Float?>(repeating: nil, count: dim),
//                    Int(Foot.rawValue): Array<Float?>(repeating: nil, count: dim),
//                    Int(Floor.rawValue): Array<Float?>(repeating: nil, count: dim) ]
//        for i in 0..<dim {
//            let value = getMedian(slice[i])
//            let groupId = slice[i].group.rawValue
//
//        }
//    }
    
    func convertToObj(separated data:[Int:[(Int,Int,Float)]]) -> [Int:String] {
        
        func writeEdges(input data: [(Int,Int,Float)]) -> String {
            
            let dim = Int(GRID_NODE_COUNT)
            
            func flagTable(_ data:[(Int,Int,Float)]) -> [[Float]] {
                var res = Array(repeating:Array(repeating: Float(), count: dim), count: dim)
                for ( i, j, val ) in data {
                    res[i][j] = val
                }
                return res
            }
            
            var res = ""
            let table = flagTable(data)
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
    
    
    
//    func exportToObjFormat() -> [Int:String] {
//
////        let acceptDist = Float(3*RADIUS) / Float(GRID_NODE_COUNT)
//
////        var res = [Int(Unknown.rawValue):"", Int(Foot.rawValue):"", Int(Floor.rawValue):""]
////        for i in 0..<renderer.myGridBuffer.count {
////            let node = renderer.myGridBuffer[i]
////            let x = gridXCoord(Int32(i))
////            let z = gridZCoord(Int32(i))
////            let y = getMedian(node)
////
////            res[Int(node.group.rawValue)]!
////                .append("v \(1000*x) \(1000*z) \(1000*y)\n")
////        }
////        return res
//
//    }

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
