import UIKit
import Metal
import MetalKit
import ARKit

class GroupedData {
    var data: [Int:String] = .init()
}

class GroupDataCoords {
    var data: [Int:[(Int, Int, Float)]] = .init()
}

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
    }
    
    @objc
    func sendAction(_ sender: UIButton!) {
        
        print("SEND!!!")
        
//        smooth()
//        renderer.separate()
        
        let data = separateData(mn: mn)
        let objects = convertToObj(separated: data)
//        let objects = exportToObjFormat()
        
        writePerId(objects)

//        renderer.currentState = Renderer.RendererState.findFootArea
        renderer.currentState.nextState()


        sendButton.isHidden = true
        startButton.isHidden = !sendButton.isHidden
    }
    
    
    func writePerId(_ objects:GroupedData) {
        
        var fNames = [Int:String].init()
        if renderer.currentState != .separate {
            fNames.updateValue("Unknown", forKey: Int(Unknown.rawValue))
            fNames.updateValue("Floor", forKey: Int(Floor.rawValue))
            fNames.updateValue("Foot", forKey: Int(Foot.rawValue))
        } else {
            for i in 0..<objects.data.count {
                fNames.updateValue(String("image-\(i)_"), forKey: i)
            }
        }

        
        var urls:[URL] = []
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first  else { return }
        
        for (id, str) in objects.data {
            if renderer.currentState != .separate {
                if id == Int(Unknown.rawValue)
					|| id == Int(Floor.rawValue)
				{ continue }
            }
            let fileName = fNames[id]! + "\(Int(Date().timeIntervalSince1970)).obj"
            let url = dir.appendingPathComponent(fileName)
            urls.append(url)
            do {
                try str.write(to: url, atomically: true, encoding: String.Encoding.utf8)
            } catch {
                print("Error!")
            }
            
        }
        
        let activity = UIActivityViewController(activityItems: urls, applicationActivities: .none)
        activity.isModalInPresentation = true
        present(activity, animated: true, completion: nil)
    }
    
    @objc
    func startAction(_ sender: UIButton!) {
        
        print("START!!!")
        if (renderer.floorHeight != -10) {
//            let nextState = isDebugMode ? Renderer.RendererState.separate: Renderer.RendererState.scanning
            renderer.currentState.nextState()
        }
        
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
    
    
    func separateData(mn:Int) -> GroupDataCoords {
        let res = GroupDataCoords()
        if renderer.currentState != .separate {
            res.data = [ Int(Unknown.rawValue):.init(),
                         Int(Foot.rawValue):.init(),
                         Int(Floor.rawValue):.init() ]
            
            for i in 0..<renderer.myGridSphericalBuffer.count {
                let node = renderer.myGridSphericalBuffer[i]
                let row = Int(gridRow(Int32(i)))
                let col = Int(gridColumn(Int32(i)))
				let val = node.median
                res.data[Int(node.group.rawValue)]!.append( (row, col, val) )

            }
            
        } else {
            for i in 0..<MAX_MESH_STATISTIC/Int32(mn) {
                res.data[Int(i)] = .init()
            }
            
            for frame in 0..<MAX_MESH_STATISTIC/Int32(mn) {
                for i in 0..<renderer.myGridSphericalBuffer.count {
                    var node = renderer.myGridSphericalBuffer[i]
                    let row = Int(gridRow(Int32(i)))
                    let col = Int(gridColumn(Int32(i)))
                    let val = getValue(&node, frame)
                    res.data[Int(frame)]!.append( (row, col, val) )
                }
            }
        }
        
        return res
        
    }
    
    func convertToObj(separated data:GroupDataCoords) -> GroupedData {
        
        func writeEdges(input data: [(Int,Int,Float)]) -> String {
            
            let dim = Int(GRID_NODE_COUNT)
			let nullsStr = "v 0 0 0\n"
            
            func fullTable(_ data:[(Int,Int,Float)]) -> [[Float]] {
                var res = Array(repeating:Array(repeating: Float(), count: dim), count: dim)
                for ( i, j, val ) in data {
                    res[i][j] = val
                }
                return res
            }
            
			
			func calcCoords(_ i:Int, _  j:Int, _ table: inout [[Float]]) -> Float3 {
				let value = table[i][j]
				let x = -calcX(Int32(i), Int32(j), value) // flip the foot
				let y = calcY(Int32(i), Int32(j), value)
				let z = calcZ(Int32(i), Int32(j), value)
				return 1000*Float3(x, y, z)
			}
			
			func isSloped(_ r1: Float3, _ r2: Float3) -> Bool {
				let dr = r2 - r1
				return abs(dr.z) > sqrt(dr.x*dr.x + dr.y*dr.y)
			}
			
			
			func smooth(_ table: inout [[Float]]) {
				for theta in 1..<dim-1 {
					for phi in 1..<dim-1 {
						var mask:[Float] = [
							table[theta-1][phi-1], table[theta-1][phi], table[theta-1][phi+1],
							table[theta][phi-1], table[theta][phi], table[theta][phi+1],
							table[theta+1][phi-1], table[theta+1][phi], table[theta+1][phi+1]
						]
						mask.sort()
						table[theta][phi] = mask[4]
						if phi == 1 {
							table[theta][0] = mask[4]
						}
						if phi == dim-2 {
							table[theta][dim-1] = mask[4]
						}
					}
				}
			}
			
			func truncateTheFloor(table: inout [[Float]]) {
				for j_phi in 0..<dim {
					var iStop:Int?
					var rhoCutted:Float?
					for i_theta in (3..<dim-1).reversed() {
						let r1 = calcCoords(i_theta - 3, j_phi, &table)
						let r2 = calcCoords(i_theta - 2, j_phi, &table)
						let r3 = calcCoords(i_theta - 1, j_phi, &table)
						let r4 = calcCoords(i_theta, j_phi, &table)
						if isSloped(r1, r2) &&
						   isSloped(r2, r3) &&
						   isSloped(r3, r4) {
							iStop = i_theta
							rhoCutted = table[i_theta][j_phi]
							break
						}
					}
					if let thetaFloor = iStop,
					   let rho = rhoCutted {
						for i_theta in thetaFloor..<dim {
							table[i_theta][j_phi] = rho
						}
					}
					
				}
				
			}
			
			
            var res = ""
            var table = fullTable(data)
			smooth(&table)
//			truncateTheFloor(table: &table)
            for i in 0..<dim {
                for j in 0..<dim {
                    var str = ""
                    if table[i][j] != Float() {
						let pos = calcCoords(i, j, &table)
						str = "v \(pos.x) \(pos.y) \(pos.z)\n"
                    } else {
                        if (renderer.currentState != .separate) {
                            str = nullsStr
                        }
                    }
                    res.append(str)
                }
            }
            
            if (renderer.currentState != .separate) {
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
            }
            
            return res
        }
        
        let res = GroupedData()
        for (key, val) in data.data {
            res.data[key] = writeEdges(input: val)
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
