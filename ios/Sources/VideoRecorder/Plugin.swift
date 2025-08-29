import Foundation
import AVFoundation
import Capacitor

extension UIColor {
    convenience init(fromHex hex: String) {
        var cString:String = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if (cString.hasPrefix("#")) {
            cString.remove(at: cString.startIndex)
        }
        var rgbValue:UInt64 = 0
        Scanner(string: cString).scanHexInt64(&rgbValue)
        self.init(
            red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
            alpha: CGFloat(1.0)
        )
    }
}

public class FrameConfig {
    var id: String
    var stackPosition: String
    var x: CGFloat
    var y: CGFloat
    var width: Any
    var height: Any
    var borderRadius: CGFloat
    var dropShadow: DropShadow
    var mirrorFrontCam: Bool

    init(_ options: [AnyHashable: Any] = [:]) {
        self.id = options["id"] as! String
        self.stackPosition = options["stackPosition"] as? String ?? "back"
        self.x = options["x"] as? CGFloat ?? 0
        self.y = options["y"] as? CGFloat ?? 0
        self.width = options["width"] ?? "fill"
        self.height = options["height"] ?? "fill"
        self.borderRadius = options["borderRadius"] as? CGFloat ?? 0
        self.dropShadow = DropShadow(options["dropShadow"] as? [AnyHashable: Any] ?? [:])
        self.mirrorFrontCam = options["mirrorFrontCam"] as? Bool ?? true
    }

    class DropShadow {
        var opacity: Float
        var radius: CGFloat
        var color: CGColor
        init(_ options: [AnyHashable: Any]) {
            self.opacity = (options["opacity"] as? NSNumber ?? 0).floatValue
            self.radius = options["radius"] as? CGFloat ?? 0
            self.color = UIColor(fromHex: options["color"] as? String ?? "#000000").cgColor
        }
    }
}

class CameraView: UIView {
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?

    func interfaceOrientationToVideoOrientation(_ orientation : UIInterfaceOrientation) -> AVCaptureVideoOrientation {
        switch (orientation) {
        case UIInterfaceOrientation.portrait:
            return AVCaptureVideoOrientation.portrait;
        case UIInterfaceOrientation.portraitUpsideDown:
            return AVCaptureVideoOrientation.portraitUpsideDown;
        case UIInterfaceOrientation.landscapeLeft:
            return AVCaptureVideoOrientation.landscapeLeft;
        case UIInterfaceOrientation.landscapeRight:
            return AVCaptureVideoOrientation.landscapeRight;
        default:
            return AVCaptureVideoOrientation.portraitUpsideDown;
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews();
        if let sublayers = self.layer.sublayers {
            for layer in sublayers {
                layer.frame = self.bounds
            }
        }
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            self.videoPreviewLayer?.connection?.videoOrientation = interfaceOrientationToVideoOrientation(windowScene.interfaceOrientation)
        }
    }

    func addPreviewLayer(_ previewLayer:AVCaptureVideoPreviewLayer?) {
        previewLayer!.videoGravity = AVLayerVideoGravity.resizeAspectFill
        previewLayer!.frame = self.bounds
        self.layer.addSublayer(previewLayer!)
        self.videoPreviewLayer = previewLayer;
    }

    func removePreviewLayer() {
        self.videoPreviewLayer?.removeFromSuperlayer()
        self.videoPreviewLayer = nil
    }
}

public func checkAuthorizationStatus(_ call: CAPPluginCall) -> Bool {
    let videoStatus = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
    if (videoStatus == AVAuthorizationStatus.restricted) {
        call.reject("Camera access restricted")
        return false
    } else if videoStatus == AVAuthorizationStatus.denied {
        call.reject("Camera access denied")
        return false
    } else if videoStatus == AVAuthorizationStatus.notDetermined {
        // For iPhone 16 Pro and iOS 18, we should request permission first
        call.reject("Camera permission not determined - please request permission first")
        return false
    }

    let audioStatus = AVCaptureDevice.authorizationStatus(for: AVMediaType.audio)
    if (audioStatus == AVAuthorizationStatus.restricted) {
        call.reject("Microphone access restricted")
        return false
    } else if audioStatus == AVAuthorizationStatus.denied {
        call.reject("Microphone access denied")
        return false
    } else if audioStatus == AVAuthorizationStatus.notDetermined {
        // For iPhone 16 Pro and iOS 18, we should request permission first
        call.reject("Microphone permission not determined - please request permission first")
        return false
    }

    return true
}

/**
 * Request camera and microphone permissions for iPhone 16 Pro compatibility
 */
public func requestPermissions(_ call: CAPPluginCall) {
    let group = DispatchGroup()
    var videoPermissionGranted = false
    var audioPermissionGranted = false
    var hasError = false

    // Request video permission
    group.enter()
    AVCaptureDevice.requestAccess(for: .video) { granted in
        videoPermissionGranted = granted
        if !granted {
            hasError = true
            call.reject("Camera permission denied")
        }
        group.leave()
    }

    // Request audio permission
    group.enter()
    AVCaptureDevice.requestAccess(for: .audio) { granted in
        audioPermissionGranted = granted
        if !granted {
            hasError = true
            call.reject("Microphone permission denied")
        }
        group.leave()
    }

    group.notify(queue: .main) {
        if !hasError && videoPermissionGranted && audioPermissionGranted {
            call.resolve(["granted": true])
        }
    }
}

enum CaptureError: Error {
    case backCameraUnavailable
    case frontCameraUnavailable
    case couldNotCaptureInput(error: NSError)
}

/**
	* Create capture input
	*/
public func createCaptureDeviceInput(currentCamera: Int, frontCamera: AVCaptureDevice?, backCamera: AVCaptureDevice?) throws -> AVCaptureDeviceInput {
	var captureDevice: AVCaptureDevice
	if (currentCamera == 0) {
		if (frontCamera != nil){
			captureDevice = frontCamera!
		} else {
			throw CaptureError.frontCameraUnavailable
		}
	} else {
		if (backCamera != nil){
			captureDevice = backCamera!
		} else {
			throw CaptureError.backCameraUnavailable
		}
	}
	let captureDeviceInput: AVCaptureDeviceInput
	do {
		captureDeviceInput = try AVCaptureDeviceInput(device: captureDevice)
	} catch let error as NSError {
		throw CaptureError.couldNotCaptureInput(error: error)
	}
	return captureDeviceInput
}

public func joinPath(left: String, right: String) -> String {
    let nsString: NSString = NSString.init(string:left);
    return nsString.appendingPathComponent(right);
}

public func randomFileName() -> String {
    return UUID().uuidString
}

@objc(VideoRecorder)
public class VideoRecorder: CAPPlugin, AVCaptureFileOutputRecordingDelegate, CAPBridgedPlugin {
    public let identifier = "VideoRecorder"
    public let jsName = "VideoRecorder"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "requestPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "initialize", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "destroy", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "flipCamera", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "toggleFlash", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "enableFlash", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "disableFlash", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isFlashAvailable", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isFlashEnabled", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "addPreviewFrameConfig", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "editPreviewFrameConfig", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "switchToPreviewFrame", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "showPreviewFrame", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "hidePreviewFrame", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "startRecording", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopRecording", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getDuration", returnType: CAPPluginReturnPromise),
    ]

    var capWebView: WKWebView!

    var cameraView: CameraView!
    var captureSession: AVCaptureSession?
    var captureVideoPreviewLayer: AVCaptureVideoPreviewLayer?
    var videoOutput: AVCaptureMovieFileOutput?
    var durationTimer: Timer?

    var audioLevelTimer: Timer?
    var audioRecorder: AVAudioRecorder?

    var cameraInput: AVCaptureDeviceInput?

    var currentCamera: Int = 0
    var frontCamera: AVCaptureDevice?
    var backCamera: AVCaptureDevice?
    var quality: Int = 0
    var videoBitrate: Int = 3000000
    var _isFlashEnabled: Bool = false

    var stopRecordingCall: CAPPluginCall?

    var previewFrameConfigs: [FrameConfig] = []
    var currentFrameConfig: FrameConfig = FrameConfig(["id": "default"])

    /**
     * Capacitor Plugin load
     */
    override public func load() {
        self.capWebView = self.bridge?.webView
    }

    /**
     * AVCaptureFileOutputRecordingDelegate
     */
    public func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        self.durationTimer?.invalidate()
        self.stopRecordingCall?.resolve([
            "videoUrl": self.bridge?.portablePath(fromLocalURL: outputFileURL)?.absoluteString as Any
        ])
    }

    @objc func levelTimerCallback(_ timer: Timer?) {
        self.audioRecorder?.updateMeters()
        // let peakDecebels: Float = (self.audioRecorder?.peakPower(forChannel: 1))!
        let averagePower: Float = (self.audioRecorder?.averagePower(forChannel: 1))!
        self.notifyListeners("onVolumeInput", data: ["value":averagePower])
    }

	/**
	* Request camera and microphone permissions - especially important for iPhone 16 Pro
	*/
    @objc override public func requestPermissions(_ call: CAPPluginCall) {
        let group = DispatchGroup()
        var videoPermissionGranted = false
        var audioPermissionGranted = false
        var hasError = false

        // Request video permission
        group.enter()
        AVCaptureDevice.requestAccess(for: .video) { granted in
            videoPermissionGranted = granted
            if !granted {
                hasError = true
                call.reject("Camera permission denied")
            }
            group.leave()
        }

        // Request audio permission
        group.enter()
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            audioPermissionGranted = granted
            if !granted {
                hasError = true
                call.reject("Microphone permission denied")
            }
            group.leave()
        }

        group.notify(queue: .main) {
            if !hasError && videoPermissionGranted && audioPermissionGranted {
                call.resolve(["granted": true])
            }
        }
    }


	/**
	* Initializes the camera.
	* { camera: Int, quality: Int }
	*/
    @objc func initialize(_ call: CAPPluginCall) {
        print("VideoRecorder: Initialize called with options: \(String(describing: call.options))")
        print("VideoRecorder: Device model: \(UIDevice.current.model), iOS version: \(UIDevice.current.systemVersion)")

        if (self.captureSession?.isRunning != true) {
            self.currentCamera = call.getInt("camera", 0)
            self.quality = call.getInt("quality", 0)
            self.videoBitrate = call.getInt("videoBitrate", 3000000)
            let autoShow = call.getBool("autoShow", true)

            for frameConfig in call.getArray("previewFrames", [ ["id": "default"] ]) {
                self.previewFrameConfigs.append(FrameConfig(frameConfig as! [AnyHashable : Any]))
            }
            self.currentFrameConfig = self.previewFrameConfigs.first!

            if checkAuthorizationStatus(call) {
                DispatchQueue.main.async { [self] in
                    do {
                        // Set webview to transparent and set the app window background to white
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                            windowScene.windows.first?.backgroundColor = UIColor.white
                        }
                        self.capWebView?.isOpaque = false
                        self.capWebView?.backgroundColor = UIColor.clear

                        // Support multiple camera types for iPhone 16 Pro and other advanced devices
                        var deviceTypes: [AVCaptureDevice.DeviceType] = [
                            .builtInWideAngleCamera
                        ]

                        // Add support for iPhone 16 Pro triple camera system
                        if #available(iOS 13.0, *) {
                            deviceTypes.append(.builtInTripleCamera)
                            deviceTypes.append(.builtInDualWideCamera)
                            deviceTypes.append(.builtInUltraWideCamera)
                        }

                        if #available(iOS 10.2, *) {
                            deviceTypes.append(.builtInDualCamera)
                        }

                        let deviceDescoverySession = AVCaptureDevice.DiscoverySession.init(
                            deviceTypes: deviceTypes,
                            mediaType: AVMediaType.video,
                            position: AVCaptureDevice.Position.unspecified)

                        print("VideoRecorder: Discovering cameras for iPhone 16 Pro compatibility...")
                        print("VideoRecorder: Available device types: \(deviceTypes)")
                        
                        for device in deviceDescoverySession.devices {
                            print("VideoRecorder: Found device - Type: \(device.deviceType), Position: \(device.position)")
                            
                            if device.position == AVCaptureDevice.Position.back {
                                // Prioritize device selection for iPhone 16 Pro compatibility
                                if self.backCamera == nil {
                                    self.backCamera = device
                                    print("VideoRecorder: Set initial back camera: \(device.deviceType)")
                                } else if device.deviceType == .builtInTripleCamera {
                                    // Triple camera is highest priority for iPhone 16 Pro
                                    self.backCamera = device
                                    print("VideoRecorder: Updated to triple camera: \(device.deviceType)")
                                } else if device.deviceType == .builtInDualWideCamera && self.backCamera?.deviceType != .builtInTripleCamera {
                                    // Dual wide camera is second priority
                                    self.backCamera = device
                                    print("VideoRecorder: Updated to dual wide camera: \(device.deviceType)")
                                } else if device.deviceType == .builtInDualCamera && 
                                         self.backCamera?.deviceType != .builtInTripleCamera &&
                                         self.backCamera?.deviceType != .builtInDualWideCamera {
                                    // Dual camera is third priority
                                    self.backCamera = device
                                    print("VideoRecorder: Updated to dual camera: \(device.deviceType)")
                                }
                            } else if device.position == AVCaptureDevice.Position.front {
                                // Apply same prioritization logic for front cameras on iPhone 16 Pro
                                if self.frontCamera == nil {
                                    self.frontCamera = device
                                    print("VideoRecorder: Set initial front camera: \(device.deviceType)")
                                } else if device.deviceType == .builtInTripleCamera {
                                    // Triple camera is highest priority for front camera too
                                    self.frontCamera = device
                                    print("VideoRecorder: Updated to front triple camera: \(device.deviceType)")
                                } else if device.deviceType == .builtInDualWideCamera && self.frontCamera?.deviceType != .builtInTripleCamera {
                                    // Dual wide camera is second priority
                                    self.frontCamera = device
                                    print("VideoRecorder: Updated to front dual wide camera: \(device.deviceType)")
                                } else if device.deviceType == .builtInDualCamera && 
                                         self.frontCamera?.deviceType != .builtInTripleCamera &&
                                         self.frontCamera?.deviceType != .builtInDualWideCamera {
                                    // Dual camera is third priority
                                    self.frontCamera = device
                                    print("VideoRecorder: Updated to front dual camera: \(device.deviceType)")
                                }
                            }
                        }
                        
                        print("VideoRecorder: Final camera selection - Back: \(self.backCamera?.deviceType ?? AVCaptureDevice.DeviceType.builtInWideAngleCamera), Front: \(self.frontCamera?.deviceType ?? AVCaptureDevice.DeviceType.builtInWideAngleCamera)")

                        // Improved fallback logic for advanced camera systems
                        if (self.backCamera == nil && self.frontCamera == nil) {
                            call.reject("No cameras available on this device")
                            return
                        }

                        // If no back camera but front camera exists, default to front
                        if (self.backCamera == nil) {
                            self.currentCamera = 0 // Use front camera
                        }

                        // Create capture session
                        self.captureSession = AVCaptureSession()
                        // Begin configuration
                        self.captureSession?.beginConfiguration()

                        self.captureSession?.automaticallyConfiguresApplicationAudioSession = false

                        /**
                         * Video file recording capture session
                         */
                        self.captureSession?.usesApplicationAudioSession = true
                        // Add Camera Input
                        self.cameraInput = try createCaptureDeviceInput(currentCamera: self.currentCamera, frontCamera: self.frontCamera, backCamera: self.backCamera)
                        self.captureSession!.addInput(self.cameraInput!)
                        
                        // Configure camera device for iPhone 16 Pro compatibility
                        if let device = self.cameraInput?.device {
                            self.configureDeviceForCompatibility(device)
                        }
                        // Add Microphone Input
                        let microphone = AVCaptureDevice.default(for: .audio)
                        if let audioInput = try? AVCaptureDeviceInput(device: microphone!), (self.captureSession?.canAddInput(audioInput))! {
                            self.captureSession!.addInput(audioInput)
                        }
                        // Add Video File Output
                        self.videoOutput = AVCaptureMovieFileOutput()
                        self.videoOutput?.movieFragmentInterval = CMTime.invalid
                        self.captureSession!.addOutput(self.videoOutput!)

                        // Set Video quality
                        switch(self.quality){
                        case 1:
                            self.captureSession?.sessionPreset = AVCaptureSession.Preset.hd1280x720
                            break;
                        case 2:
                            self.captureSession?.sessionPreset = AVCaptureSession.Preset.hd1920x1080
                            break;
                        case 3:
                            self.captureSession?.sessionPreset = AVCaptureSession.Preset.hd4K3840x2160
                            break;
                        case 4:
                            self.captureSession?.sessionPreset = AVCaptureSession.Preset.high
                            break;
                        case 5:
                            self.captureSession?.sessionPreset = AVCaptureSession.Preset.low
                            break;
                        case 6:
                            self.captureSession?.sessionPreset = AVCaptureSession.Preset.cif352x288
                            break;
                        default:
                            self.captureSession?.sessionPreset = AVCaptureSession.Preset.vga640x480
                            break;
                        }

                        let connection: AVCaptureConnection? = self.videoOutput?.connection(with: .video)
                        self.videoOutput?.setOutputSettings([AVVideoCodecKey : AVVideoCodecType.h264], for: connection!)

                        // Commit configurations
                        self.captureSession?.commitConfiguration()


                        do {
                            try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playAndRecord, mode: AVAudioSession.Mode.default, options: [
                                .mixWithOthers,
                                .defaultToSpeaker,
                                .allowBluetoothA2DP,
                                .allowAirPlay
                            ])
                        } catch {
                            print("Failed to set audio session category.")
                        }
                        try? AVAudioSession.sharedInstance().setActive(true)
                        let settings = [
                            AVSampleRateKey : 44100.0,
                            AVFormatIDKey : kAudioFormatAppleLossless,
                            AVNumberOfChannelsKey : 2,
                            AVEncoderAudioQualityKey : AVAudioQuality.max.rawValue
                            ] as [String : Any]
                        self.audioRecorder = try AVAudioRecorder(url: URL(fileURLWithPath: "/dev/null"), settings: settings)
                        self.audioRecorder?.isMeteringEnabled = true
                        self.audioRecorder?.prepareToRecord()
                        self.audioRecorder?.record()
                        self.audioLevelTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(self.levelTimerCallback(_:)), userInfo: nil, repeats: true)
                        self.audioRecorder?.updateMeters()

                        // Start running sessions
                        self.captureSession!.startRunning()

                        // Initialize camera view
                        self.initializeCameraView()

                        if autoShow {
                            self.cameraView.isHidden = false
                        }
                        
                        // Log camera capabilities for debugging iPhone 16 Pro issues
                        self.logCameraCapabilities()

                    } catch CaptureError.backCameraUnavailable {
                        print("VideoRecorder: Initialize failed - Back camera unavailable")
                        call.reject("Back camera unavailable")
                    } catch CaptureError.frontCameraUnavailable {
                        print("VideoRecorder: Initialize failed - Front camera unavailable")
                        call.reject("Front camera unavailable")
                    } catch CaptureError.couldNotCaptureInput(let error) {
                        print("VideoRecorder: Initialize failed - Could not capture input: \(error)")
                        call.reject("Camera unavailable")
                    } catch {
                        print("VideoRecorder: Initialize failed - Unexpected error: \(error)")
                        call.reject("Unexpected error")
                    }
                    
                    print("VideoRecorder: Initialize completed successfully")
                    call.resolve()
                }
            }
        }
    }

	/**
	* Destroys the camera.
	*/
    @objc func destroy(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let appDelegate = UIApplication.shared.delegate
            appDelegate?.window?!.backgroundColor = UIColor.black

            self.capWebView?.isOpaque = true
            self.capWebView?.backgroundColor = UIColor.white
            if (self.captureSession != nil) {
				// Need to destroy all preview layers
                self.previewFrameConfigs = []
                self.currentFrameConfig = FrameConfig(["id": "default"])
                if (self.captureSession!.isRunning) {
                    self.captureSession!.stopRunning()
                }
                if (self.audioRecorder != nil && self.audioRecorder!.isRecording) {
                    self.audioRecorder!.stop()
                }
                self.cameraView?.removePreviewLayer()
                self.captureVideoPreviewLayer = nil
                self.cameraView?.removeFromSuperview()
                self.videoOutput = nil
                self.cameraView = nil
                self.captureSession = nil
                self.audioRecorder = nil
                self.audioLevelTimer?.invalidate()
                self.currentCamera = 0
                self.frontCamera = nil
                self.backCamera = nil
                self.notifyListeners("onVolumeInput", data: ["value":0])
            }
            call.resolve()
        }
    }

	/**
	* Toggle between the front facing and rear facing camera.
	*/
    @objc func flipCamera(_ call: CAPPluginCall) {
        print("VideoRecorder: flipCamera called - Current camera: \(self.currentCamera)")
        
        guard self.captureSession != nil else {
            print("VideoRecorder: No capture session available")
            call.reject("Camera session not initialized")
            return
        }
        
        guard self.captureSession!.isRunning else {
            print("VideoRecorder: Capture session is not running")
            call.reject("Camera session not running")
            return
        }

        let newCamera = self.currentCamera == 0 ? 1 : 0
        print("VideoRecorder: Attempting to switch to camera: \(newCamera)")
        
        // Check if target camera is available
        if newCamera == 0 && self.frontCamera == nil {
            print("VideoRecorder: Front camera not available")
            call.reject("Front camera unavailable")
            return
        }
        
        if newCamera == 1 && self.backCamera == nil {
            print("VideoRecorder: Back camera not available") 
            call.reject("Back camera unavailable")
            return
        }

        var input: AVCaptureDeviceInput? = nil
        do {
            self.currentCamera = newCamera
            input = try createCaptureDeviceInput(currentCamera: self.currentCamera, frontCamera: self.frontCamera, backCamera: self.backCamera)
            print("VideoRecorder: Successfully created input for camera: \(self.currentCamera)")
        } catch CaptureError.backCameraUnavailable {
            self.currentCamera = self.currentCamera == 0 ? 1 : 0
            print("VideoRecorder: Back camera unavailable error")
            call.reject("Back camera unavailable")
            return
        } catch CaptureError.frontCameraUnavailable {
            self.currentCamera = self.currentCamera == 0 ? 1 : 0
            print("VideoRecorder: Front camera unavailable error")
            call.reject("Front camera unavailable")
            return
        } catch CaptureError.couldNotCaptureInput(let error) {
            self.currentCamera = self.currentCamera == 0 ? 1 : 0
            print("VideoRecorder: Could not capture input error: \(error)")
            call.reject("Camera unavailable: \(error.localizedDescription)")
            return
        } catch {
            self.currentCamera = self.currentCamera == 0 ? 1 : 0
            print("VideoRecorder: Unexpected error: \(error)")
            call.reject("Unexpected error: \(error.localizedDescription)")
            return
        }

        guard let newInput = input else {
            print("VideoRecorder: Failed to create camera input")
            call.reject("Failed to create camera input")
            return
        }

        let currentInput = self.cameraInput
        
        // Begin session configuration
        self.captureSession?.beginConfiguration()
        
        // Remove current input
        if let currentInput = currentInput {
            print("VideoRecorder: Removing current input: \(currentInput.device.deviceType)")
            self.captureSession?.removeInput(currentInput)
        }
        
        // Add new input
        if self.captureSession!.canAddInput(newInput) {
            self.captureSession!.addInput(newInput)
            self.cameraInput = newInput
            print("VideoRecorder: Successfully added new input: \(newInput.device.deviceType)")
        } else {
            // Rollback on failure
            if let currentInput = currentInput {
                self.captureSession!.addInput(currentInput)
                self.cameraInput = currentInput
            }
            self.captureSession?.commitConfiguration()
            self.currentCamera = self.currentCamera == 0 ? 1 : 0
            print("VideoRecorder: Cannot add new camera input")
            call.reject("Cannot add new camera input")
            return
        }
        
        // Configure the new camera device for iPhone 16 Pro compatibility
        configureDeviceForCompatibility(newInput.device)
        
        // Commit configuration
        self.captureSession?.commitConfiguration()
        print("VideoRecorder: Successfully committed session configuration")

        // Update camera view to apply correct mirroring for the new camera
        DispatchQueue.main.async {
            self.updateCameraView(self.currentFrameConfig)
            print("VideoRecorder: Updated camera view for new camera")
        }

        call.resolve()
        print("VideoRecorder: flipCamera completed successfully")
    }
    
    /**
     * Configure camera device for iPhone 16 Pro compatibility
     */
    func configureDeviceForCompatibility(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            
            print("VideoRecorder: Configuring device for compatibility: \(device.deviceType)")
            
            // Configure triple camera systems
            if device.deviceType == .builtInTripleCamera {
                // Set initial zoom factor to 2x to avoid ultra-wide fisheye effect
                if device.videoZoomFactor < 2.0 && device.maxAvailableVideoZoomFactor >= 2.0 {
                    device.videoZoomFactor = 2.0
                    print("VideoRecorder: Set zoom factor to 2x for triple camera")
                }
                
                // Note: primaryConstituentDeviceSwitchingBehavior is read-only and automatically managed by the system
                if #available(iOS 15.0, *) {
                    print("VideoRecorder: Triple camera auto switching behavior: \(device.primaryConstituentDeviceSwitchingBehavior.rawValue)")
                }
            }
            
            // Configure dual wide camera systems 
            else if device.deviceType == .builtInDualWideCamera {
                if #available(iOS 15.0, *) {
                    print("VideoRecorder: Dual wide camera auto switching behavior: \(device.primaryConstituentDeviceSwitchingBehavior.rawValue)")
                }
            }
            
            // Configure dual camera systems
            else if device.deviceType == .builtInDualCamera {
                if #available(iOS 15.0, *) {
                    print("VideoRecorder: Dual camera auto switching behavior: \(device.primaryConstituentDeviceSwitchingBehavior.rawValue)")
                }
            }
            
            device.unlockForConfiguration()
        } catch {
            print("VideoRecorder: Failed to configure camera device: \(error)")
        }
    }
    
    /**
     * Debug helper to print all available camera information
     */
    func logCameraCapabilities() {
        print("VideoRecorder: === Camera Capabilities Debug ===")
        
        if let frontDevice = self.frontCamera {
            print("VideoRecorder: Front camera - Type: \(frontDevice.deviceType), Unique ID: \(frontDevice.uniqueID)")
            print("VideoRecorder: Front camera - Min zoom: \(frontDevice.minAvailableVideoZoomFactor), Max zoom: \(frontDevice.maxAvailableVideoZoomFactor)")
            if #available(iOS 15.0, *) {
                print("VideoRecorder: Front camera - Switching behavior: \(frontDevice.primaryConstituentDeviceSwitchingBehavior.rawValue)")
            }
        } else {
            print("VideoRecorder: Front camera - Not available")
        }
        
        if let backDevice = self.backCamera {
            print("VideoRecorder: Back camera - Type: \(backDevice.deviceType), Unique ID: \(backDevice.uniqueID)")
            print("VideoRecorder: Back camera - Min zoom: \(backDevice.minAvailableVideoZoomFactor), Max zoom: \(backDevice.maxAvailableVideoZoomFactor)")
            if #available(iOS 15.0, *) {
                print("VideoRecorder: Back camera - Switching behavior: \(backDevice.primaryConstituentDeviceSwitchingBehavior.rawValue)")
            }
        } else {
            print("VideoRecorder: Back camera - Not available")
        }
        
        print("VideoRecorder: Current camera index: \(self.currentCamera)")
        print("VideoRecorder: Capture session running: \(self.captureSession?.isRunning ?? false)")
        print("VideoRecorder: === End Camera Capabilities Debug ===")
    }

	/**
	* Add a camera preview frame config.
	*/
    @objc func addPreviewFrameConfig(_ call: CAPPluginCall) {
        if (self.captureSession != nil) {
            guard let layerId = call.getString("id") else {
                call.reject("Must provide layer id")
                return
            }
			let newFrame = FrameConfig(call.options)

            // Check to make sure config doesn't already exist, if it does, edit it instead
            if (self.previewFrameConfigs.firstIndex(where: {$0.id == layerId }) == nil) {
                self.previewFrameConfigs.append(newFrame)
            }
            else {
                self.editPreviewFrameConfig(call)
                return
            }
			call.resolve()
        }
    }

	/**
	* Edit an existing camera frame config.
	*/
    @objc func editPreviewFrameConfig(_ call: CAPPluginCall) {
        if (self.captureSession != nil) {
            guard let layerId = call.getString("id") else {
                call.reject("Must provide layer id")
                return
            }

            let updatedConfig = FrameConfig(call.options)

            // Get existing frame config
            let existingConfig = self.previewFrameConfigs.filter( {$0.id == layerId }).first
            if (existingConfig != nil) {
                let index = self.previewFrameConfigs.firstIndex(where: {$0.id == layerId })
                self.previewFrameConfigs[index!] = updatedConfig
            }
            else {
                self.addPreviewFrameConfig(call)
                return
            }

            if (self.currentFrameConfig.id == layerId) {
                // Is set to the current frame, need to update
                DispatchQueue.main.async {
                    self.currentFrameConfig = updatedConfig
                    self.updateCameraView(self.currentFrameConfig)
                }
            }
            call.resolve()
        }
    }

    /**
     * Switch frame configs.
     */
    @objc func switchToPreviewFrame(_ call: CAPPluginCall) {
        if (self.captureSession != nil) {
            guard let layerId = call.getString("id") else {
                call.reject("Must provide layer id")
                return
            }
            DispatchQueue.main.async {
                let existingConfig = self.previewFrameConfigs.filter( {$0.id == layerId }).first
                if (existingConfig != nil) {
                    if (existingConfig!.id != self.currentFrameConfig.id) {
                        self.currentFrameConfig = existingConfig!
                        self.updateCameraView(self.currentFrameConfig)
                    }
                }
                else {
                    call.reject("Frame config does not exist")
                    return
                }
                call.resolve()
            }
        }
    }

	/**
	* Show the camera preview frame.
	*/
    @objc func showPreviewFrame(_ call: CAPPluginCall) {
        if (self.captureSession != nil) {
            DispatchQueue.main.async {
                self.cameraView.isHidden = true
                call.resolve()
            }
        }
    }

	/**
	* Hide the camera preview frame.
	*/
    @objc func hidePreviewFrame(_ call: CAPPluginCall) {
        if (self.captureSession != nil) {
            DispatchQueue.main.async {
                self.cameraView.isHidden = false
                call.resolve()
            }
        }
    }

    func initializeCameraView() {
        self.cameraView = CameraView(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        self.cameraView.isHidden = true
        self.cameraView.autoresizingMask = [.flexibleWidth, .flexibleHeight];
        self.captureVideoPreviewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession!)
        self.captureVideoPreviewLayer?.frame = self.cameraView.bounds
        self.cameraView.addPreviewLayer(self.captureVideoPreviewLayer)

        self.cameraView.backgroundColor = UIColor.black
        self.cameraView.videoPreviewLayer?.masksToBounds = true
        self.cameraView.clipsToBounds = false
        self.cameraView.layer.backgroundColor = UIColor.clear.cgColor

        self.capWebView!.superview!.insertSubview(self.cameraView, belowSubview: self.capWebView!)

        self.updateCameraView(self.currentFrameConfig)
    }

    func updateCameraView(_ config: FrameConfig) {
        // Set position and dimensions
        let width = config.width as? String == "fill" ? UIScreen.main.bounds.width : config.width as! CGFloat
        let height = config.height as? String == "fill" ? UIScreen.main.bounds.height : config.height as! CGFloat
        self.cameraView.frame = CGRect(x: config.x, y: config.y, width: width, height: height)

        // Set stackPosition
        if config.stackPosition == "front" {
            self.capWebView!.superview!.bringSubviewToFront(self.cameraView)
        }
        else if config.stackPosition == "back" {
            self.capWebView!.superview!.sendSubviewToBack(self.cameraView)
        }

        // Set decorations
        self.cameraView.videoPreviewLayer?.cornerRadius = config.borderRadius
        self.cameraView.layer.shadowOffset = CGSize.zero
        self.cameraView.layer.shadowColor = config.dropShadow.color
        self.cameraView.layer.shadowOpacity = config.dropShadow.opacity
        self.cameraView.layer.shadowRadius = config.dropShadow.radius
        self.cameraView.layer.shadowPath = UIBezierPath(roundedRect: self.cameraView.bounds, cornerRadius: config.borderRadius).cgPath

        // Set mirroring based on config.mirrorFrontCam property (only for front camera, mirrored by default)
        if let connection = self.cameraView.videoPreviewLayer?.connection {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = self.currentCamera == 0 ? config.mirrorFrontCam : false
        }
        
        // Refresh camera preview layer for iPhone 16 Pro compatibility
        self.refreshCameraPreview()
    }
    
    func refreshCameraPreview() {
        DispatchQueue.main.async {
            // Force refresh the preview layer to handle iPhone 16 Pro display issues
            if let previewLayer = self.cameraView?.videoPreviewLayer {
                previewLayer.setNeedsLayout()
                previewLayer.layoutIfNeeded()
                
                // Ensure the connection is properly configured
                if let connection = previewLayer.connection {
                    connection.isEnabled = false
                    connection.isEnabled = true
                }
            }
        }
    }

	/**
	* Start recording.
	*/
    @objc func startRecording(_ call: CAPPluginCall) {
        if (self.captureSession != nil) {
            if (!(videoOutput?.isRecording)!) {
                let tempDir = NSURL.fileURL(withPath:NSTemporaryDirectory(), isDirectory: true)
                var fileName = randomFileName()
                fileName.append(".mp4")
                let fileUrl = NSURL.fileURL(withPath: joinPath(left: tempDir.path, right: fileName))

                // Configure video output settings
                let videoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: self.videoBitrate
                    ]
                ]

                if let connection = self.videoOutput?.connection(with: .video) {
                    self.videoOutput?.setOutputSettings(videoSettings, for: connection)
                }

                DispatchQueue.main.async {
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        self.videoOutput?.connection(with: .video)?.videoOrientation = self.cameraView.interfaceOrientationToVideoOrientation(windowScene.interfaceOrientation)
                    }

                    // Apply mirroring setting to video output connection (saved video should never be mirrored to match Android behavior)
                    if let connection = self.videoOutput?.connection(with: .video) {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = false
                    }
                    // turn on flash if flash is enabled and camera is back camera
                    if (self.currentCamera == 1 && self._isFlashEnabled) {
                        let device = AVCaptureDevice.default(for: .video)
                        if let device = device {
                            do {
                                try device.lockForConfiguration()
                                try device.setTorchModeOn(level: 1.0)
                                device.unlockForConfiguration()
                            } catch {
                                // ignore error
                            }
                        }
                    }
                    self.videoOutput?.startRecording(to: fileUrl, recordingDelegate: self)
                    call.resolve()
                }
            }
        }
    }

	/**
	* Stop recording.
	*/
    @objc func stopRecording(_ call: CAPPluginCall) {
        if (self.captureSession != nil) {
            if (videoOutput?.isRecording)! {
                self.stopRecordingCall = call
                self.videoOutput!.stopRecording()

                // turn off flash if flash is enabled and camera is back camera
                if (self.currentCamera == 1 && self._isFlashEnabled) {
                    let device = AVCaptureDevice.default(for: .video)
                    if let device = device {
                        do {
                            try device.lockForConfiguration()
                            device.torchMode = .off
                            device.unlockForConfiguration()
                        } catch {
                            // ignore error
                        }
                    }
                }
            }
        }
    }

	/**
	* Get current recording duration.
	*/
    @objc func getDuration(_ call: CAPPluginCall) {
        if (self.videoOutput!.isRecording == true) {
            let duration = self.videoOutput?.recordedDuration;
            if (duration != nil) {
                call.resolve(["value":round(CMTimeGetSeconds(duration!))])
            } else {
                call.resolve(["value":0])
            }
        } else {
            call.resolve(["value":0])
        }
    }

    @objc func isFlashAvailable(_ call: CAPPluginCall) {
        if (self.captureSession != nil) {
            let device = AVCaptureDevice.default(for: .video)
            if let device = device {
                call.resolve(["isAvailable": device.hasTorch])
            } else {
                call.resolve(["isAvailable": false])
            }
        }
    }

    @objc func isFlashEnabled(_ call: CAPPluginCall) {
        call.resolve(["isEnabled": self._isFlashEnabled])
    }

    @objc func enableFlash(_ call: CAPPluginCall) {
        self._isFlashEnabled = true
        call.resolve()
    }

    @objc func disableFlash(_ call: CAPPluginCall) {
        self._isFlashEnabled = false
        call.resolve()
    }

    @objc func toggleFlash(_ call: CAPPluginCall) {
        self._isFlashEnabled = !self._isFlashEnabled
        call.resolve()
    }
}
