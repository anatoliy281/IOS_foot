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
    }
    
    @objc
    func sendAction(_ sender: UIButton!) {
        
        print("SEND!!!")
        
		let meshHoler = MeshHolder(renderer)
		let objects = meshHoler.convertToObj()
        
        writePerId(objects)

//        renderer.currentState = Renderer.RendererState.findFootArea
        renderer.currentState.nextState()


        sendButton.isHidden = true
        startButton.isHidden = !sendButton.isHidden
    }
    
    
    func writePerId(_ objects: GroupedData) {
		var ignoreList = [Int]()
		if renderer.currentState != .separate {
			ignoreList.append(Int(Unknown.rawValue))
			ignoreList.append(Int(Floor.rawValue))
		}
								 
        
        var fNames = [Int:String].init()
        if renderer.currentState != .separate {
            fNames.updateValue("Unknown", forKey: Int(Unknown.rawValue))
            fNames.updateValue("Floor", forKey: Int(Floor.rawValue))
            fNames.updateValue("Foot", forKey: Int(Foot.rawValue))
			fNames.updateValue("CleanFoot", forKey: Int(Foot.rawValue)+1)
        } else {
			for i in 0..<objects.data.count {
                fNames.updateValue(String("image-\(i)_"), forKey: i)
            }
        }

        
        var urls:[URL] = []
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first  else { return }
        
		for (id, str) in objects.data {
			if ignoreList.contains(id) { continue }
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
