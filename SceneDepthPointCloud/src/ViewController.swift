import UIKit
import Metal
import MetalKit
import ARKit



final class ViewController: UIViewController, ARSessionDelegate {
    private let isUIEnabled = true
    private let sendButton = UIButton(frame: CGRect(x: 100, y:100, width: 100, height: 50));
    private let startButton = UIButton(frame: CGRect(x: 100, y:100, width: 100, height: 50));
	public let switchMetricModeButton = UIButton(frame: CGRect(x: 100, y:100, width: 100, height: 50));
	public var info = UILabel(frame: CGRect(x: 30, y: 30, width: 400, height: 100))
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
		info.numberOfLines = 5
		info.adjustsFontSizeToFitWidth = false
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
        
        stackView = UIStackView(arrangedSubviews: [startButton, sendButton, switchMetricModeButton])
        sendButton.isHidden = true
		switchMetricModeButton.isHidden = true
        stackView.isHidden = !isUIEnabled
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 20
        view.addSubview(stackView)
		view.addSubview(info)
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -50)
        ])
    }
    
    @objc
    func sendAction(_ sender: UIButton!) {
        
        print("SEND!!!")
		info.text = "Обработка данных..."
		let meshHolder = MeshHolder(renderer)
        sendPostRequest(meshHolder)
    }
	
    func sendPostRequest(_ meshHolder: MeshHolder) {
		
		// show info on view and activate button
		func updateUi(_ str: String) {
			DispatchQueue.main.async { [self] in
				info.text = str
				startButton.isHidden = false
			}
		}
		
		sendButton.isHidden = true
		let objects = meshHolder.convertToObj()
		guard let strData = objects.data[Int(Foot.rawValue)] else { return }
		let side = String("0")
		
		
		let boundary = "Boundary-\(UUID().uuidString)"
		// Prepare URL
		guard let requestUrl = URL(string: "http://35.242.213.112:3441/mobile_obj_to_vox") else { fatalError() }
		// Prepare URL Request Object
		var request = URLRequest(url: requestUrl)
		request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
		request.httpMethod = "POST"

		var postString = ""
		postString += "--\(boundary)\r\n"
		postString += "Content-Disposition:form-data; name=\"side\""
		postString += "\r\n\r\n\(side)\r\n"
		
		postString += "--\(boundary)\r\n"
		postString += "Content-Disposition:form-data; name=\"file\""
		postString += "; filename=\"file.obj\"\r\n"
		  + "Content-Type: \"content-type header\"\r\n\r\n\(strData)\r\n"
		postString += "--\(boundary)--\r\n";
		
		request.httpBody = postString.data(using: .utf8);
		request.timeoutInterval = 300
		
		let task = URLSession.shared.dataTask(with: request) { [self] (data, response, error) in
				
			// Convert HTTP Response Data to a String
			if data != nil {
				print("data not nil")
				if let convertedJsonIntoDict = try? JSONSerialization.jsonObject(with: data!, options: []) as? NSDictionary {
						// Print out entire dictionary
//						print(convertedJsonIntoDict)
						// Get value by key
					let length = convertedJsonIntoDict["length"]! as! Double
					
					let width_bones = convertedJsonIntoDict["girth"]! as! [String:Double]
					let fascGirth = width_bones["bones"]!
					
					let arcLength = convertedJsonIntoDict["arcLength"]! as! Double
					
					let width_other = convertedJsonIntoDict["width_other"]! as! [String:Double]
					let heelWidth = width_other["heel"]!
					
					let resultText = String("Длина: \(Int(round(length))), обхват в пучках: \(Int(round(fascGirth))), длина арки: \(Int(round(arcLength))), ширина пятки: \(Int(round(heelWidth)))")
					
					updateUi(resultText)
					print("data OK")
				} else {
					let resultText = "Ошибка (code=1)"
					updateUi(resultText)
					print("json error")
				}
			} else {
				if error == nil {
					updateUi("Oшибка (code=0)")
					print("error nil")
					return
				}
				updateUi(error.debugDescription)
				print("data nil!!! " + error.debugDescription)
				return
			}
			renderer.currentState.nextState()
		}
		task.resume()
	}
    
	@objc
    func startAction(_ sender: UIButton!) {
		info.text = ""
        print("START!!!")
		if (renderer.pointCloudUniforms.floorHeight != -10) {
//            let nextState = isDebugMode ? Renderer.RendererState.separate: Renderer.RendererState.scanning
            renderer.currentState.nextState()
        }
//		switchMetricModeButton.isHidden = false
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
