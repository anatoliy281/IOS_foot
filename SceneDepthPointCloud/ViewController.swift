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
    private let myButton = UIButton(frame: CGRect(x: 100, y:100, width: 100, height: 50));
    
//    private let rgbRadiusSlider = UISlider()
    
    private let session = ARSession()
    private var renderer: Renderer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        myButton.backgroundColor = .green
        myButton.setTitle("Send!", for: .normal)
        myButton.addTarget(self, action: #selector(buttonAction), for: .touchUpInside)
        view.addSubview(myButton)
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
        
        let stackView = UIStackView(arrangedSubviews: [myButton])
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
    func buttonAction(_ sender: UIButton!) {

        // в метрах
        let radius:Float = 0.5
        let dim:Int = 500
        let dR:Float = 2*radius / Float(dim)    // средний шаг сетки
        var chunks = Array(repeating:Array(repeating:[SIMD3<Float>](), count:dim),
                           count:dim)
        
        for p in renderer.getCloud() {
            if (p.x*p.x + p.z*p.z < radius*radius) {
                let i = Int(p.x/dR) + dim/2
                let j = Int(p.z/dR) + dim/2
                chunks[i][j].append(p)
            }
        }
        
        let meanGrid = calcGridInMm(grid: chunks, dim: dim)
        let obj = exportToObjFormat(grid: meanGrid, dim:dim)
        
        let step:Float = 5  // шаг гистограммы высот
        let gistro = calcHeightGisto(grid:meanGrid, step:step, dim:dim)
        let floor = findFloor(gistro:gistro, step:step, grid:meanGrid, dim:dim)
        let floorObj = exportToObjFormat(points: floor)
        
        let meanGridEven = calcGridInMmEven(grid: chunks, dim: dim, dR: dR)
        let floorHeight = calcFloorHeight(floor)
        let floorishMesh = setNullToFloorPoints(meanGridEven, dim, dR, floorHeight)
        let floorishMedianFilteredMesh = filterMaskMedian(floorishMesh, dim)
        
        let objEven = exportToObjFormat(grid: floorishMedianFilteredMesh, dim:dim)
        
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let file = "cloud.obj"
            let fileGridURL = dir.appendingPathComponent(file)
            
            let fileEven = "cloudEven.obj"
            let fileGridEvenURL = dir.appendingPathComponent(fileEven)
            
            let floorFile = "floor.obj"
            let fileFloorURL = dir.appendingPathComponent(floorFile)
            
            
            //writing
            do {
                try obj.write(to: fileGridURL, atomically: true, encoding: String.Encoding.utf8)
                try objEven.write(to: fileGridEvenURL, atomically: true, encoding: String.Encoding.utf8)
                try floorObj.write(to: fileFloorURL, atomically: true, encoding: String.Encoding.utf8)
            }
            catch {/* error handling here */}
            
            let activity = UIActivityViewController(activityItems: [fileFloorURL, fileGridURL, fileGridEvenURL],
                                                    applicationActivities: .none)
            activity.isModalInPresentation = true
            present(activity, animated: true, completion: nil)
        }
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
    
//    @objc
//    private func viewValueChanged(view: UIView) {
//        switch view {
//
//        case rgbRadiusSlider:
//            renderer.rgbRadius = rgbRadiusSlider.value
//
//        default:
//            break
//        }
//    }
    
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
    
    func calcGridInMm(grid: [[[SIMD3<Float>]]], dim: Int) -> [[SIMD3<Float>]] {
        var res = Array(repeating:Array(repeating:SIMD3<Float>(), count:dim), count:dim)
        for i in 0..<dim {
            for j in 0..<dim {
                let statisticData = grid[i][j]
                var p = SIMD3<Float>()
                if statisticData.count > 0 {
                    let gridSorted = statisticData.sorted {
                        $0.y < $1.y
                    }
                    p = gridSorted[gridSorted.count/2]
                }
                res[i][j] = 1000*p
            }
        }
        return res
    }
    
    func calcGridInMmEven(grid: [[[SIMD3<Float>]]], dim: Int, dR: Float) -> [[SIMD3<Float>]] {
        var res = Array(repeating:Array(repeating:SIMD3<Float>(), count:dim), count:dim)
        for i in 0..<dim {
            for j in 0..<dim {
                let statisticData = grid[i][j]
                var p = SIMD3<Float>()
                if statisticData.count > 0 {
                    let gridSorted = statisticData.sorted {
                        $0.y < $1.y
                    }
                    p = gridSorted[gridSorted.count/2]
                    p.x = indexToPos(i, dim, dR)
                    p.z = indexToPos(j, dim, dR)
                }
                res[i][j] = 1000*p
            }
        }
        
        return res
    }
    
    func calcHeightGisto(grid: [[SIMD3<Float>]], step: Float, dim: Int) -> [Float:Int] {
        var res = [Float:Int]()
        for i in 0..<dim {
            for j in 0..<dim {
                let h = grid[i][j].y
                let hDescr = floor(h/step)*step
                if let cnt = res[hDescr] {
                    res[hDescr] = cnt + 1
                } else {
                    res[hDescr] = 1
                }
            }
        }
        return res
    }
    
    func findFloor(gistro: [Float:Int], step: Float, grid: [[SIMD3<Float>]], dim: Int) -> [SIMD3<Float>] {
        var res = [SIMD3<Float>]()
        
        var maxCount:Int = 0
        var floorHeight:Float = 0
        for el in gistro {
            if el.key != 0 {
                if (el.value > maxCount) {
                    floorHeight = el.key
                    maxCount = el.value
                }
            }
        }
        
        for i in 0..<dim {
            for j in 0..<dim {
                let p = grid[i][j]
                let delta = p.y - floorHeight
                if (delta < step && delta > 0) {
                    res.append(p)
                }
            }
        }
        
        return res
    }
    
    func calcFloorHeight(_ floorPoints: [SIMD3<Float>]) -> Float {
        let sortedPoints = floorPoints.sorted {
            $0.y > $1.y
        }
        return sortedPoints[sortedPoints.count/2].y
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
    
    
    func findFloorRing(points: [SIMD3<Float>]) -> (SIMD3<Float>, Float, Float) {
        let N = Float(points.count)
        var xMean:Float = 0
        var yMean:Float = 0
        var zMean:Float = 0
        for p in points {
            xMean += p.x
            yMean += p.y
            zMean += p.z
        }
        xMean /= N
        yMean /= N
        zMean /= N
        
        var r1:Float = 0
        var r2:Float = 0
        for p in points {
            let rho2 = (p.x - xMean)*(p.x - xMean) + (p.z - zMean)*(p.z - zMean)
            r1 += rho2
            r2 += sqrt(rho2)
        }
        
        return (SIMD3<Float>(xMean, yMean, zMean), sqrt(r1/N), r2/N)
    }
    
    func exportToObjFormat(grid: [[SIMD3<Float>]], dim: Int) -> String {
//      vertexes
        var text: String = ""
        for i in 0..<dim {
            for j in 0..<dim {
                let p = grid[i][j]
                text.append("v \(p.x) \(p.y) \(p.z)\n")
            }
        }
        
        let zero = SIMD3<Float>.zero
        
//      edges connecting vertex pair
        for i in 1..<dim-1 {
            for j in 1..<dim-1 {
                if (grid[i][j] != zero) {
                    let pos = i*dim + j + 1
                    if (grid[i][j+1] != zero) {
                        text.append("l \(pos) \(pos + 1)\n")
                    }
                    if (grid[i+1][j] != zero) {
                        text.append("l \(pos) \(pos + dim)\n")
                    }
                }
            }
        }
        return text
    }
    
    func exportToObjFormat(points: [SIMD3<Float>]) -> String {
//      vertexes
        var text: String = ""
        for p in points {
            text.append("v \(p.x) \(p.y) \(p.z)\n")
        }
        
        return text
    }
    
    func exportToObjFormat(center:SIMD3<Float>, radius:Float) -> String {
//      vertexes
        var text: String = ""
        let xMean = center[0]
        let yMean = center[1]
        let zMean = center[2]

        let n:Int = 12
        let dx = 2*radius / Float(n)
        for i in 0...n {
            let x0 = Float(i)*dx - radius
            let x = xMean + x0
            let z0 = sqrt(radius*radius - x0*x0)
            text.append("v \(x) \(yMean) \(zMean-z0)\n")
            text.append("v \(x) \(yMean) \(zMean+z0)\n")
        }
        
        return text
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
