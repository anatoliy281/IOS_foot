import UIKit
import Metal
import MetalKit
import ARKit



final class ViewController: UIViewController, ARSessionDelegate {
    private let isUIEnabled = true
    private let sendButton = UIButton(frame: CGRect(x: 100, y:100, width: 100, height: 50));
    private let startButton = UIButton(frame: CGRect(x: 100, y:100, width: 100, height: 50));
	public let switchMetricModeButton = UIButton(frame: CGRect(x: 100, y:100, width: 100, height: 50));
	public var info = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 50))
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
		
		switchMetricModeButton.backgroundColor = .gray
		switchMetricModeButton.setTitle("Снять длину", for: .normal)
		switchMetricModeButton.addTarget(self, action: #selector(acceptMetricPropAction), for: .touchUpInside)
		
		info.font = UIFont(name: "Palatino", size: 30)
		info.textColor = UIColor(red: 0, green: 1, blue: 1, alpha: 1)
		
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
			renderer.label = info
        }
        
        stackView = UIStackView(arrangedSubviews: [startButton, sendButton, switchMetricModeButton, info])
        sendButton.isHidden = true
		switchMetricModeButton.isHidden = true
        stackView.isHidden = !isUIEnabled
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
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

		let meshHolder = MeshHolder(renderer)
        writePerId(meshHolder)

//        renderer.currentState = Renderer.RendererState.findFootArea
        renderer.currentState.nextState()


        sendButton.isHidden = true
        startButton.isHidden = false
    }
    
    
    func writePerId(_ meshHolder: MeshHolder) {
		
		// список игнорирования данных для записи
		var ignoreList = [Int]()
		if renderer.currentState != .separate {
			ignoreList.append(Int(Unknown.rawValue))
//			ignoreList.append(Int(Floor.rawValue))
		}
		let objects = meshHolder.convertToObj()
        let fNames = generateFileCaptionDict(meshHolder)
		
		// запись данных meshHolder в соответствующие файлы с именами из fNames
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
	
	private func generateFileCaptionDict(_ meshHolder: MeshHolder) -> [Int:String] {
		let fNames:[Int:String] = [ Int(Unknown.rawValue): "Unknown",
									Int(Floor.rawValue): "Floor",
									Int(Border.rawValue): "Border",
									Int(Foot.rawValue): "Foot"
								]
		return fNames
	}
    
	@objc
    func startAction(_ sender: UIButton!) {
        
        print("START!!!")
		if (renderer.pointCloudUniforms.floorHeight != -10) {
//            let nextState = isDebugMode ? Renderer.RendererState.separate: Renderer.RendererState.scanning
            renderer.currentState.nextState()
        }
		switchMetricModeButton.isHidden = false
        sendButton.isHidden = false
        startButton.isHidden = true
		
    }
	
	@objc
	func acceptMetricPropAction(_ sender: UIButton!) {
		print("ACCEPT METRIC!!!")
		var caption:String
		renderer.currentMeasured = 0
		renderer.controlPoint.reset()
		

		
		if (renderer.metricMode == .lengthToe) {
			caption = "Снятие длины"
		} else if (renderer.metricMode == .lengthHeel) {
			let a = renderer.footMetric.length.a.mean
			let b = renderer.footMetric.length.b.mean
			let dr = a - b
			let intres = Int(round(1000*length(Float2(dr.x, dr.y))))
			caption = "Снятие пучков /(Длина: \(intres))"
		} else if (renderer.metricMode == .bunchWidthOuter) {
			caption = "Снятие пучков"
		} else if renderer.metricMode == .bunchWidthInner {
			let a = renderer.footMetric.bunchWidth.a.mean
			let b = renderer.footMetric.bunchWidth.b.mean
			let dr = a - b
			let intres = Int(round(1000*length(Float2(dr.x, dr.y))))
			caption = "Снятие высоты: /(Пучки: \(intres))"
		} else if renderer.metricMode == .heightInRise {
			let h = renderer.footMetric.heightInRise.mean
			let intres = Int(round(1000*h.z))
			caption = "Снятие длины: /(Высота: \(intres))"
		} else {
			caption = ""
		}
		renderer.nextMetricStep()
		switchMetricModeButton.setTitle(caption, for: .normal)
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
