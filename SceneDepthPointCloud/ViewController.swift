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
    private let confidenceControl = UISegmentedControl(items: ["Low", "Medium", "High"])
    private let myButton = UIButton(frame: CGRect(x: 100, y:100, width: 100, height: 50));
    
    private let rgbRadiusSlider = UISlider()
    
    private let session = ARSession()
    private var renderer: Renderer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        myButton.backgroundColor = .green
        myButton.setTitle("---", for: .normal)
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
        
        // Confidence control
        
//        renderer.confidenceThreshold = 2
        confidenceControl.backgroundColor = .white
        confidenceControl.selectedSegmentIndex = renderer.confidenceThreshold
        confidenceControl.addTarget(self, action: #selector(viewValueChanged), for: .valueChanged)
        
        // RGB Radius control
        rgbRadiusSlider.minimumValue = 0
        rgbRadiusSlider.maximumValue = 1.5
        rgbRadiusSlider.isContinuous = true
        rgbRadiusSlider.value = renderer.rgbRadius
        rgbRadiusSlider.addTarget(self, action: #selector(viewValueChanged), for: .valueChanged)
        
        let stackView = UIStackView(arrangedSubviews: [confidenceControl, rgbRadiusSlider])
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
//        session.pause()

        let radius:Float = 0.5
        let dim:Int = 200
        let dR:Float = 2*radius / Float(dim)
        let cld = [SIMD3<Float>]()
        let xS = Array(repeating: cld, count: dim)
        var chunks = Array(repeating: xS, count: dim)
        
        for p in renderer.getCloud() {
            if (p.x*p.x + p.z*p.z < radius*radius) {
                let i = Int(p.x/dR) + dim/2
                let j = Int(p.z/dR) + dim/2
                chunks[i][j].append(p)
            }
        }
        
        let meanGrid = calcMeanGridInMm(grid: chunks, dim: dim)
        let obj = exportToObjFormat(grid: meanGrid, dim:dim)
        
        let step:Float = 5
        let gistro = calcHeightGisto(grid:meanGrid, step:step, dim:dim)
        let floor = findFloor(gistro:gistro, step:step, grid:meanGrid, dim:dim)
        let floorObj = exportToObjFormat(points: floor)
        
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let file = "cloud.obj"
            let fileGridURL = dir.appendingPathComponent(file)
            
            let floorFile = "floor.obj"
            let fileFloorURL = dir.appendingPathComponent(floorFile)
           
            //writing
            do {
                try obj.write(to: fileGridURL, atomically: true, encoding: String.Encoding.utf8)
                try floorObj.write(to: fileFloorURL, atomically: true, encoding: String.Encoding.utf8)
            }
            catch {/* error handling here */}
            
            let activity = UIActivityViewController(activityItems: [fileFloorURL, fileGridURL],
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
    
    @objc
    private func viewValueChanged(view: UIView) {
        switch view {
            
        case confidenceControl:
            renderer.confidenceThreshold = confidenceControl.selectedSegmentIndex
            
        case rgbRadiusSlider:
            renderer.rgbRadius = rgbRadiusSlider.value
            
        default:
            break
        }
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
    
    func calcMeanGridInMm(grid: [[[SIMD3<Float>]]], dim: Int) -> [[SIMD3<Float>]] {
        var res = [[SIMD3<Float>]]()
        for i in 0..<dim {
            var row = [SIMD3<Float>]()
            for j in 0..<dim {
                let statisticData = grid[i][j]
                var pMean = SIMD3<Float>()
                if (!statisticData.isEmpty) {
                    for p in statisticData {
                        pMean += p
                    }
                    pMean /= Float(statisticData.count)
                }
                row.append(1000*pMean) // also convert in mm
            }
            res.append(row)
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
