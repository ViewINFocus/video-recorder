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
        guard let previewLayer = previewLayer else { return }

        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        previewLayer.frame = self.bounds

        // Ensure proper layer positioning for iPhone 16 Pro
        self.layer.addSublayer(previewLayer)
        self.videoPreviewLayer = previewLayer

        // Force immediate layout update
        previewLayer.setNeedsLayout()
        previewLayer.layoutIfNeeded()

        print("VideoRecorder: Preview layer added - Frame: \(previewLayer.frame), Session: \(previewLayer.session != nil)")
    }

    func removePreviewLayer() {
        self.videoPreviewLayer?.removeFromSuperlayer()
        self.videoPreviewLayer = nil
    }
}

public func checkAuthorizationStatus(_ call: CAPPluginCall) -> Bool {
    print("VideoRecorder: === PERMISSION STATUS DEBUG ===")
    print("VideoRecorder: iOS Version: \(UIDevice.current.systemVersion)")
    print("VideoRecorder: Device Model: \(UIDevice.current.model)")
    print("VideoRecorder: Device Name: \(UIDevice.current.name)")

    let videoStatus = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
    print("VideoRecorder: Video permission status: \(videoStatus.rawValue) (0=notDetermined, 1=restricted, 2=denied, 3=authorized)")

    if (videoStatus == AVAuthorizationStatus.restricted) {
        print("VideoRecorder: ERROR - Camera access restricted by system policy")
        call.reject("Camera access restricted")
        return false
    } else if videoStatus == AVAuthorizationStatus.denied {
        print("VideoRecorder: ERROR - Camera access denied by user")
        call.reject("Camera access denied")
        return false
    } else if videoStatus == AVAuthorizationStatus.notDetermined {
        print("VideoRecorder: ERROR - Camera permission not determined - iOS 18 requires explicit permission request")
        call.reject("Camera permission not determined - please request permission first")
        return false
    } else if videoStatus == AVAuthorizationStatus.authorized {
        print("VideoRecorder: SUCCESS - Camera permission authorized")
    }

    let audioStatus = AVCaptureDevice.authorizationStatus(for: AVMediaType.audio)
    print("VideoRecorder: Audio permission status: \(audioStatus.rawValue) (0=notDetermined, 1=restricted, 2=denied, 3=authorized)")

    if (audioStatus == AVAuthorizationStatus.restricted) {
        print("VideoRecorder: ERROR - Microphone access restricted by system policy")
        call.reject("Microphone access restricted")
        return false
    } else if audioStatus == AVAuthorizationStatus.denied {
        print("VideoRecorder: ERROR - Microphone access denied by user")
        call.reject("Microphone access denied")
        return false
    } else if audioStatus == AVAuthorizationStatus.notDetermined {
        print("VideoRecorder: ERROR - Microphone permission not determined - iOS 18 requires explicit permission request")
        call.reject("Microphone permission not determined - please request permission first")
        return false
    } else if audioStatus == AVAuthorizationStatus.authorized {
        print("VideoRecorder: SUCCESS - Microphone permission authorized")
    }

    print("VideoRecorder: === PERMISSION STATUS CHECK PASSED ===")
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
        print("VideoRecorder: === PLUGIN INITIALIZATION START ===")
        print("VideoRecorder: Initialize called with options: \(String(describing: call.options))")
        print("VideoRecorder: Device model: \(UIDevice.current.model)")
        print("VideoRecorder: iOS version: \(UIDevice.current.systemVersion)")
        print("VideoRecorder: Device name: \(UIDevice.current.name)")
        print("VideoRecorder: System uptime: \(ProcessInfo.processInfo.systemUptime) seconds")

        // Check if this is iPhone 16 Pro specifically
        let deviceName = UIDevice.current.name.lowercased()
        let isIPhone16Pro = deviceName.contains("iphone 16 pro")
        print("VideoRecorder: iPhone 16 Pro detected: \(isIPhone16Pro)")

        // Check iOS 18 specific version
        let iOSVersion = UIDevice.current.systemVersion
        let isIOS18 = iOSVersion.hasPrefix("18.")
        print("VideoRecorder: iOS 18 detected: \(isIOS18)")

        if isIPhone16Pro && isIOS18 {
            print("VideoRecorder: WARNING - CRITICAL DEVICE COMBO - iPhone 16 Pro + iOS 18 detected")
            print("VideoRecorder: Applying enhanced debugging and compatibility measures")
        }

        print("VideoRecorder: Checking if session is already running...")
        if let session = self.captureSession {
            print("VideoRecorder: Existing session found - Running: \(session.isRunning)")
            if session.isRunning {
                print("VideoRecorder: Session already running, skipping initialization")
                call.resolve()
                return
            }
        } else {
            print("VideoRecorder: No existing session found, proceeding with initialization")
        }

        if (self.captureSession?.isRunning != true) {
            self.currentCamera = call.getInt("camera", 0)
            self.quality = call.getInt("quality", 0)
            self.videoBitrate = call.getInt("videoBitrate", 3000000)
            let autoShow = call.getBool("autoShow", true)

            for frameConfig in call.getArray("previewFrames", [ ["id": "default"] ]) {
                self.previewFrameConfigs.append(FrameConfig(frameConfig as! [AnyHashable : Any]))
            }
            self.currentFrameConfig = self.previewFrameConfigs.first!

            print("VideoRecorder: Checking authorization status...")
            if checkAuthorizationStatus(call) {
                print("VideoRecorder: Authorization status check passed, proceeding with initialization...")
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

                        print("VideoRecorder: === CAMERA DISCOVERY DEBUG ===")
                        print("VideoRecorder: Searching for iPhone 16 Pro compatible cameras...")
                        print("VideoRecorder: Available device types: \(deviceTypes)")
                        print("VideoRecorder: Total devices discovered: \(deviceDescoverySession.devices.count)")

                        if deviceDescoverySession.devices.isEmpty {
                            print("VideoRecorder: CRITICAL ERROR - No camera devices found at all!")
                            call.reject("No camera devices available on this device")
                            return
                        }

                        for (index, device) in deviceDescoverySession.devices.enumerated() {
                            print("VideoRecorder: Device[\(index)] - Type: \(device.deviceType.rawValue), Position: \(device.position.rawValue), Name: \(device.localizedName)")
                            print("VideoRecorder: Device[\(index)] - UniqueID: \(device.uniqueID)")
                            print("VideoRecorder: Device[\(index)] - Connected: \(device.isConnected)")

                            // Check device availability
                            if !device.isConnected {
                                print("VideoRecorder: WARNING - Device[\(index)] is not connected")
                            }
                            // Note: isInUseByAnotherApplication is only available on macOS

                            if device.position == AVCaptureDevice.Position.back {
                                // For iPhone 16 Pro, prioritize standard wide angle camera initially for better compatibility
                                if self.backCamera == nil {
                                    self.backCamera = device
                                    print("VideoRecorder: Set initial back camera: \(device.deviceType)")
                                } else if device.deviceType == .builtInWideAngleCamera && self.backCamera?.deviceType != .builtInWideAngleCamera {
                                    // For iPhone 16 Pro stability, prefer wide angle camera
                                    self.backCamera = device
                                    print("VideoRecorder: Updated to wide angle camera for iPhone 16 Pro compatibility: \(device.deviceType)")
                                } else if device.deviceType == .builtInTripleCamera && self.backCamera?.deviceType == .builtInWideAngleCamera {
                                    // Keep wide angle for now, but store triple camera as backup
                                    print("VideoRecorder: Found triple camera but keeping wide angle for startup: \(device.deviceType)")
                                } else if device.deviceType == .builtInDualWideCamera && self.backCamera?.deviceType != .builtInWideAngleCamera && self.backCamera?.deviceType != .builtInTripleCamera {
                                    // Dual wide camera is lower priority
                                    self.backCamera = device
                                    print("VideoRecorder: Updated to dual wide camera: \(device.deviceType)")
                                } else if device.deviceType == .builtInDualCamera &&
                                         self.backCamera?.deviceType != .builtInWideAngleCamera &&
                                         self.backCamera?.deviceType != .builtInTripleCamera &&
                                         self.backCamera?.deviceType != .builtInDualWideCamera {
                                    // Dual camera is lowest priority
                                    self.backCamera = device
                                    print("VideoRecorder: Updated to dual camera: \(device.deviceType)")
                                }
                            } else if device.position == AVCaptureDevice.Position.front {
                                // Apply same prioritization logic for front cameras on iPhone 16 Pro
                                if self.frontCamera == nil {
                                    self.frontCamera = device
                                    print("VideoRecorder: Set initial front camera: \(device.deviceType)")
                                } else if device.deviceType == .builtInWideAngleCamera && self.frontCamera?.deviceType != .builtInWideAngleCamera {
                                    // Prefer wide angle for front camera too
                                    self.frontCamera = device
                                    print("VideoRecorder: Updated to front wide angle camera: \(device.deviceType)")
                                } else if device.deviceType == .builtInTripleCamera && self.frontCamera?.deviceType == .builtInWideAngleCamera {
                                    // Keep wide angle for stability
                                    print("VideoRecorder: Found front triple camera but keeping wide angle: \(device.deviceType)")
                                } else if device.deviceType == .builtInDualWideCamera && self.frontCamera?.deviceType != .builtInWideAngleCamera && self.frontCamera?.deviceType != .builtInTripleCamera {
                                    // Dual wide camera is second priority
                                    self.frontCamera = device
                                    print("VideoRecorder: Updated to front dual wide camera: \(device.deviceType)")
                                } else if device.deviceType == .builtInDualCamera &&
                                         self.frontCamera?.deviceType != .builtInWideAngleCamera &&
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

                        print("VideoRecorder: === CAPTURE SESSION INITIALIZATION ===")

                        // Create capture session
                        self.captureSession = AVCaptureSession()
                        guard let session = self.captureSession else {
                            print("VideoRecorder: CRITICAL ERROR - Failed to create AVCaptureSession")
                            call.reject("Failed to create capture session")
                            return
                        }

                        // Add session interruption observers for iPhone 16 Pro compatibility
                        NotificationCenter.default.addObserver(
                            forName: .AVCaptureSessionWasInterrupted,
                            object: session,
                            queue: .main
                        ) { notification in
                            print("VideoRecorder: Session was interrupted")
                            if let reasonValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int,
                               let reason = AVCaptureSession.InterruptionReason(rawValue: reasonValue) {
                                print("VideoRecorder: Interruption reason: \(reason)")
                            }
                        }
                        
                        NotificationCenter.default.addObserver(
                            forName: .AVCaptureSessionInterruptionEnded,
                            object: session,
                            queue: .main
                        ) { notification in
                            print("VideoRecorder: Session interruption ended")
                        }

                        NotificationCenter.default.addObserver(
                            forName: .AVCaptureSessionRuntimeError,
                            object: session,
                            queue: .main
                        ) { notification in
                            print("VideoRecorder: Session runtime error")
                            if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error {
                                print("VideoRecorder: Runtime error: \(error)")
                            }
                        }

                        print("VideoRecorder: AVCaptureSession created successfully")
                        if #available(iOS 16.0, *) {
                            print("VideoRecorder: Session supports multi-cam: \(session.isMultitaskingCameraAccessSupported)")
                        } else {
                            print("VideoRecorder: Multi-cam support check requires iOS 16.0+")
                        }

                        // Begin configuration
                        print("VideoRecorder: Beginning session configuration...")
                        session.beginConfiguration()

                        session.automaticallyConfiguresApplicationAudioSession = false
                        print("VideoRecorder: Set automaticallyConfiguresApplicationAudioSession = false")

                        /**
                         * Video file recording capture session
                         */
                        session.usesApplicationAudioSession = true
                        print("VideoRecorder: Set usesApplicationAudioSession = true")

                        print("VideoRecorder: === CAMERA INPUT CONFIGURATION ===")

                        // Add Camera Input with enhanced error handling for iPhone 16 Pro
                        do {
                            print("VideoRecorder: Creating camera input for camera index: \(self.currentCamera)")
                            print("VideoRecorder: Front camera available: \(self.frontCamera != nil)")
                            print("VideoRecorder: Back camera available: \(self.backCamera != nil)")

                            if self.currentCamera == 0 && self.frontCamera == nil {
                                print("VideoRecorder: ERROR - Requested front camera but none available")
                                throw CaptureError.frontCameraUnavailable
                            }
                            if self.currentCamera == 1 && self.backCamera == nil {
                                print("VideoRecorder: ERROR - Requested back camera but none available")
                                throw CaptureError.backCameraUnavailable
                            }

                            self.cameraInput = try createCaptureDeviceInput(currentCamera: self.currentCamera, frontCamera: self.frontCamera, backCamera: self.backCamera)

                            guard let cameraInput = self.cameraInput else {
                                print("VideoRecorder: CRITICAL ERROR - Camera input creation returned nil")
                                call.reject("Camera input creation failed")
                                return
                            }

                            print("VideoRecorder: Camera input created successfully")
                            print("VideoRecorder: Selected device: \(cameraInput.device.deviceType.rawValue)")
                            print("VideoRecorder: Device name: \(cameraInput.device.localizedName)")
                            print("VideoRecorder: Device position: \(cameraInput.device.position.rawValue)")
                            print("VideoRecorder: Device connected: \(cameraInput.device.isConnected)")
                            // Note: Device usage check not available on iOS

                            // Check if device is actually available for use
                            if !cameraInput.device.isConnected {
                                print("VideoRecorder: ERROR - Selected camera device is not connected")
                                call.reject("Camera device not connected")
                                return
                            }

                            // Note: isInUseByAnotherApplication is only available on macOS

                            // Verify we can add the camera input before proceeding
                            if session.canAddInput(cameraInput) {
                                session.addInput(cameraInput)
                                print("VideoRecorder: SUCCESS - Camera input successfully added to session")
                                print("VideoRecorder: Session now has \(session.inputs.count) input(s)")
                            } else {
                                print("VideoRecorder: ERROR - Cannot add camera input to session")
                                print("VideoRecorder: Session inputs count: \(session.inputs.count)")
                                print("VideoRecorder: Session outputs count: \(session.outputs.count)")
                                call.reject("Cannot add camera input to session")
                                return
                            }
                        } catch CaptureError.frontCameraUnavailable {
                            print("VideoRecorder: ERROR - Front camera unavailable")
                            call.reject("Front camera unavailable")
                            return
                        } catch CaptureError.backCameraUnavailable {
                            print("VideoRecorder: ERROR - Back camera unavailable")
                            call.reject("Back camera unavailable")
                            return
                        } catch CaptureError.couldNotCaptureInput(let nsError) {
                            print("VideoRecorder: ERROR - Could not create capture input: \(nsError)")
                            print("VideoRecorder: NSError code: \(nsError.code), domain: \(nsError.domain)")
                            print("VideoRecorder: NSError userInfo: \(nsError.userInfo)")
                            call.reject("Failed to create camera input: \(nsError.localizedDescription)")
                            return
                        } catch {
                            print("VideoRecorder: ERROR - Unexpected error creating camera input: \(error)")
                            call.reject("Failed to create camera input: \(error.localizedDescription)")
                            return
                        }

                        // Configure camera device for iPhone 16 Pro compatibility
                        if let device = self.cameraInput?.device {
                            self.configureDeviceForCompatibility(device)
                        }
                        print("VideoRecorder: === MICROPHONE INPUT CONFIGURATION ===")

                        // Add Microphone Input
                        let microphone = AVCaptureDevice.default(for: .audio)
                        if let micDevice = microphone {
                            print("VideoRecorder: Microphone device found: \(micDevice.localizedName)")
                            print("VideoRecorder: Microphone connected: \(micDevice.isConnected)")
                            // Note: Device usage check not available on iOS

                            do {
                                let audioInput = try AVCaptureDeviceInput(device: micDevice)
                                if session.canAddInput(audioInput) {
                                    session.addInput(audioInput)
                                    print("VideoRecorder: SUCCESS - Audio input successfully added")
                                    print("VideoRecorder: Session now has \(session.inputs.count) input(s)")
                                } else {
                                    print("VideoRecorder: ERROR - Cannot add audio input to session")
                                }
                            } catch {
                                print("VideoRecorder: ERROR - Failed to create audio input: \(error)")
                            }
                        } else {
                            print("VideoRecorder: ERROR - No microphone device available")
                        }

                        print("VideoRecorder: === VIDEO OUTPUT CONFIGURATION ===")

                        // Add Video File Output
                        self.videoOutput = AVCaptureMovieFileOutput()
                        guard let videoOutput = self.videoOutput else {
                            print("VideoRecorder: CRITICAL ERROR - Failed to create AVCaptureMovieFileOutput")
                            call.reject("Failed to create video output")
                            return
                        }

                        videoOutput.movieFragmentInterval = CMTime.invalid
                        print("VideoRecorder: Video output created successfully")

                        // Verify we can add the video output
                        if session.canAddOutput(videoOutput) {
                            session.addOutput(videoOutput)
                            print("VideoRecorder: SUCCESS - Video output successfully added to session")
                            print("VideoRecorder: Session now has \(session.outputs.count) output(s)")
                        } else {
                            print("VideoRecorder: ERROR - Cannot add video output to session")
                            print("VideoRecorder: Session inputs: \(session.inputs.count), outputs: \(session.outputs.count)")
                            call.reject("Cannot add video output to session")
                            return
                        }

                        // Set Video quality with iPhone 16 Pro specific handling
                        let sessionPreset: AVCaptureSession.Preset
                        switch(self.quality){
                        case 1:
                            sessionPreset = AVCaptureSession.Preset.hd1280x720
                        case 2:
                            sessionPreset = AVCaptureSession.Preset.hd1920x1080
                        case 3:
                            sessionPreset = AVCaptureSession.Preset.hd4K3840x2160
                        case 4:
                            sessionPreset = AVCaptureSession.Preset.high
                        case 5:
                            sessionPreset = AVCaptureSession.Preset.low
                        case 6:
                            sessionPreset = AVCaptureSession.Preset.cif352x288
                        default:
                            sessionPreset = AVCaptureSession.Preset.vga640x480
                        }

                        print("VideoRecorder: === SESSION PRESET CONFIGURATION ===")
                        print("VideoRecorder: Requested preset: \(sessionPreset.rawValue) (quality: \(self.quality))")

                        // Check if the session preset is supported by iPhone 16 Pro
                        if session.canSetSessionPreset(sessionPreset) {
                            session.sessionPreset = sessionPreset
                            print("VideoRecorder: SUCCESS - Session preset set to: \(sessionPreset.rawValue)")
                        } else {
                            print("VideoRecorder: WARNING - Requested preset \(sessionPreset.rawValue) not supported")

                            // Test all presets to see what's available
                            let allPresets: [AVCaptureSession.Preset] = [
                                .hd4K3840x2160,
                                .hd1920x1080,
                                .hd1280x720,
                                .high,
                                .medium,
                                .low,
                                .vga640x480,
                                .cif352x288,
                                .inputPriority
                            ]

                            print("VideoRecorder: Testing all available presets:")
                            for preset in allPresets {
                                let supported = session.canSetSessionPreset(preset)
                                print("VideoRecorder: Preset \(preset.rawValue): \(supported ? "SUPPORTED" : "NOT SUPPORTED")")
                            }

                            // Fallback to highest supported preset for iPhone 16 Pro
                            let fallbackPresets: [AVCaptureSession.Preset] = [
                                .hd4K3840x2160,
                                .hd1920x1080,
                                .hd1280x720,
                                .high,
                                .medium,
                                .low,
                                .vga640x480,
                                .inputPriority
                            ]

                            var presetSet = false
                            for preset in fallbackPresets {
                                if session.canSetSessionPreset(preset) {
                                    session.sessionPreset = preset
                                    print("VideoRecorder: SUCCESS - Using fallback preset: \(preset.rawValue)")
                                    presetSet = true
                                    break
                                }
                            }

                            if !presetSet {
                                print("VideoRecorder: CRITICAL ERROR - No supported session presets found!")
                            }
                        }

                        let connection: AVCaptureConnection? = self.videoOutput?.connection(with: .video)
                        self.videoOutput?.setOutputSettings([AVVideoCodecKey : AVVideoCodecType.h264], for: connection!)

                        print("VideoRecorder: === COMMITTING SESSION CONFIGURATION ===")
                        print("VideoRecorder: About to commit session configuration...")
                        print("VideoRecorder: Session inputs before commit: \(session.inputs.count)")
                        print("VideoRecorder: Session outputs before commit: \(session.outputs.count)")

                        // Commit configurations with error handling for iPhone 16 Pro
                        session.commitConfiguration()
                        print("VideoRecorder: Session configuration committed successfully")

                        // Verify session configuration was successful
                        print("VideoRecorder: === SESSION CONFIGURATION VERIFICATION ===")
                        print("VideoRecorder: Session inputs after commit: \(session.inputs.count)")
                        print("VideoRecorder: Session outputs after commit: \(session.outputs.count)")
                        print("VideoRecorder: Session preset: \(session.sessionPreset.rawValue)")
                        print("VideoRecorder: Session interrupted: \(session.isInterrupted)")
                        print("VideoRecorder: Session running: \(session.isRunning)")

                        if session.inputs.isEmpty {
                            print("VideoRecorder: CRITICAL ERROR - Session has no inputs after configuration!")
                            call.reject("Session configuration failed - no inputs")
                            return
                        }

                        if session.outputs.isEmpty {
                            print("VideoRecorder: CRITICAL ERROR - Session has no outputs after configuration!")
                            call.reject("Session configuration failed - no outputs")
                            return
                        }

                        // Log all inputs for debugging iPhone 16 Pro issues
                        for (index, input) in session.inputs.enumerated() {
                            if let deviceInput = input as? AVCaptureDeviceInput {
                                print("VideoRecorder: Input[\(index)]: \(deviceInput.device.deviceType.rawValue) - \(deviceInput.device.localizedName)")
                                print("VideoRecorder: Input[\(index)]: Connected=\(deviceInput.device.isConnected)")

                                // Check for specific iPhone 16 Pro camera capabilities
                                if deviceInput.device.deviceType == .builtInTripleCamera {
                                    print("VideoRecorder: Triple camera detected - checking capabilities")
                                    if #available(iOS 15.0, *) {
                                        print("VideoRecorder: Triple camera switching behavior: \(deviceInput.device.primaryConstituentDeviceSwitchingBehavior.rawValue)")
                                    }
                                }
                            }
                        }

                        // Log all outputs
                        for (index, output) in session.outputs.enumerated() {
                            print("VideoRecorder: Output[\(index)]: \(type(of: output))")
                            if let movieOutput = output as? AVCaptureMovieFileOutput {
                                print("VideoRecorder: Movie output connections: \(movieOutput.connections.count)")
                                for (connIndex, connection) in movieOutput.connections.enumerated() {
                                    let mediaType = connection.inputPorts.first?.mediaType ?? AVMediaType.video
                                    print("VideoRecorder: Connection[\(connIndex)]: \(mediaType.rawValue), enabled: \(connection.isEnabled), active: \(connection.isActive)")
                                }
                            }
                        }


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

                        // Enhanced session startup with iPhone 16 Pro + iOS 18 compatibility
                        print("VideoRecorder: === ENHANCED SESSION STARTUP ===")
                        
                        if let session = self.captureSession {
                            // Pre-startup diagnostics
                            print("VideoRecorder: Pre-startup session state:")
                            print("VideoRecorder: - Session can start running: \(session.canSetSessionPreset(session.sessionPreset))")
                            print("VideoRecorder: - Session interrupted: \(session.isInterrupted)")
                            print("VideoRecorder: - Session running: \(session.isRunning)")
                            
                            // Check for potential blocking conditions on iPhone 16 Pro
                            var startupAttempts = 0
                            let maxAttempts = 3
                            var sessionStarted = false
                            
                            while !sessionStarted && startupAttempts < maxAttempts {
                                startupAttempts += 1
                                print("VideoRecorder: Session startup attempt \(startupAttempts)/\(maxAttempts)")
                                
                                // For iPhone 16 Pro, ensure session is completely stopped before starting
                                if session.isRunning {
                                    print("VideoRecorder: Session unexpectedly running, stopping first...")
                                    session.stopRunning()
                                    // Brief pause to ensure full stop
                                    usleep(100000) // 100ms
                                }
                                
                                // Add session interruption handling for iPhone 16 Pro
                                if session.isInterrupted {
                                    print("VideoRecorder: Session is interrupted, waiting for restoration...")
                                    // Wait for interruption to clear
                                    var waitCount = 0
                                    while session.isInterrupted && waitCount < 10 {
                                        usleep(100000) // 100ms
                                        waitCount += 1
                                    }
                                    
                                    if session.isInterrupted {
                                        print("VideoRecorder: Session interruption did not clear after 1 second")
                                        if startupAttempts == maxAttempts {
                                            call.reject("Camera session interrupted and could not be restored")
                                            return
                                        }
                                        continue
                                    }
                                }
                                
                                // Try different approaches for iPhone 16 Pro camera startup
                                if startupAttempts == 1 {
                                    print("VideoRecorder: Attempt 1 - Direct session start")
                                    session.startRunning()
                                } else if startupAttempts == 2 {
                                    print("VideoRecorder: Attempt 2 - Session start with preset reset")
                                    session.beginConfiguration()
                                    let currentPreset = session.sessionPreset
                                    session.sessionPreset = .medium  // Safe fallback
                                    session.commitConfiguration()
                                    session.startRunning()
                                    // Wait and check if it started
                                    usleep(200000) // 200ms
                                    if !session.isRunning {
                                        // Restore original preset and try again
                                        session.beginConfiguration()
                                        session.sessionPreset = currentPreset
                                        session.commitConfiguration()
                                        session.startRunning()
                                    }
                                } else if startupAttempts == 3 {
                                    print("VideoRecorder: Attempt 3 - Minimal configuration with input priority preset")
                                    session.beginConfiguration()
                                    session.sessionPreset = .inputPriority
                                    session.commitConfiguration()
                                    session.startRunning()
                                }
                                
                                // Give session time to start on iPhone 16 Pro
                                usleep(300000) // 300ms
                                
                                print("VideoRecorder: Session start attempt \(startupAttempts) completed - Running: \(session.isRunning)")
                                
                                if session.isRunning {
                                    sessionStarted = true
                                    print("VideoRecorder: SUCCESS - Session started on attempt \(startupAttempts)")
                                    
                                    // Additional verification for iPhone 16 Pro camera activation
                                    if let cameraInput = self.cameraInput {
                                        print("VideoRecorder: Camera device active: \(cameraInput.device.deviceType)")
                                        print("VideoRecorder: Camera device connected: \(cameraInput.device.isConnected)")
                                        
                                        // Verify camera is actually responding
                                        do {
                                            try cameraInput.device.lockForConfiguration()
                                            print("VideoRecorder: Camera device configuration lock successful")
                                            cameraInput.device.unlockForConfiguration()
                                        } catch {
                                            print("VideoRecorder: WARNING - Camera device not responding: \(error)")
                                        }
                                    }
                                    
                                    // Final session state verification
                                    print("VideoRecorder: Final session verification:")
                                    print("VideoRecorder: - Running: \(session.isRunning)")
                                    print("VideoRecorder: - Interrupted: \(session.isInterrupted)")
                                    print("VideoRecorder: - Preset: \(session.sessionPreset.rawValue)")
                                    
                                    break
                                } else {
                                    print("VideoRecorder: Session startup attempt \(startupAttempts) failed")
                                    
                                    // Enhanced diagnostics for failed attempt
                                    print("VideoRecorder: Failed attempt diagnostics:")
                                    print("VideoRecorder: - Session interrupted: \(session.isInterrupted)")
                                    print("VideoRecorder: - Session preset supported: \(session.canSetSessionPreset(session.sessionPreset))")
                                    print("VideoRecorder: - Input count: \(session.inputs.count)")
                                    print("VideoRecorder: - Output count: \(session.outputs.count)")
                                    
                                    // Check if camera device is still available
                                    if let cameraInput = self.cameraInput {
                                        print("VideoRecorder: - Camera still connected: \(cameraInput.device.isConnected)")
                                    }
                                }
                            }
                            
                            if !sessionStarted {
                                print("VideoRecorder: CRITICAL ERROR - All session startup attempts failed!")
                                print("VideoRecorder: This appears to be an iPhone 16 Pro + iOS 18 compatibility issue")
                                call.reject("Camera session failed to start after multiple attempts - iPhone 16 Pro compatibility issue")
                                return
                            }
                        } else {
                            print("VideoRecorder: CRITICAL ERROR - No capture session available")
                            call.reject("No capture session available")
                            return
                        }

                        // Initialize camera view
                        self.initializeCameraView()

                        if autoShow {
                            self.cameraView.isHidden = false
                            print("VideoRecorder: Camera view auto-shown")
                        }

                        // Log camera capabilities for debugging iPhone 16 Pro issues
                        self.logCameraCapabilities()

                        // Additional delay for iPhone 16 Pro to ensure preview appears
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if self.cameraView.isHidden == false {
                                self.refreshCameraPreview()
                                print("VideoRecorder: Delayed preview refresh completed")
                            }
                        }

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

                    print("VideoRecorder: === INITIALIZATION COMPLETED ===")
                    print("VideoRecorder: Initialize completed successfully")

                    // Final verification for iPhone 16 Pro
                    if let session = self.captureSession {
                        print("VideoRecorder: Final session state:")
                        print("VideoRecorder: - Running: \(session.isRunning)")
                        print("VideoRecorder: - Inputs: \(session.inputs.count)")
                        print("VideoRecorder: - Outputs: \(session.outputs.count)")
                        print("VideoRecorder: - Preset: \(session.sessionPreset.rawValue)")
                    }

                    call.resolve()
                }
            } else {
                print("VideoRecorder: Authorization status check failed, initialization aborted")
                return
            }
        } else {
            print("VideoRecorder: Session already running, skipping initialization")
            call.resolve()
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
            print("VideoRecorder: Capture session is not running - attempting to start session")

            // Try to start the session for iPhone 16 Pro
            if let session = self.captureSession {
                DispatchQueue.global(qos: .userInitiated).async {
                    session.startRunning()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if session.isRunning {
                            print("VideoRecorder: Session started successfully, retrying camera flip")
                            self.flipCamera(call)  // Retry the flip operation
                        } else {
                            print("VideoRecorder: Failed to start session for camera flip")
                            call.reject("Camera session could not be started")
                        }
                    }
                }
                return
            } else {
                call.reject("Camera session not running")
                return
            }
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
                // For iPhone 16 Pro, start with 1x zoom instead of 2x to ensure camera starts properly
                if device.videoZoomFactor != 1.0 && device.minAvailableVideoZoomFactor <= 1.0 {
                    device.videoZoomFactor = 1.0
                    print("VideoRecorder: Set zoom factor to 1x for triple camera initial setup")
                }

                // Configure focus mode for better iPhone 16 Pro performance
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                    print("VideoRecorder: Set continuous auto focus for triple camera")
                }

                // Configure exposure mode
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                    print("VideoRecorder: Set continuous auto exposure for triple camera")
                }

                // Note: primaryConstituentDeviceSwitchingBehavior is read-only and automatically managed by the system
                if #available(iOS 15.0, *) {
                    print("VideoRecorder: Triple camera auto switching behavior: \(device.primaryConstituentDeviceSwitchingBehavior.rawValue)")
                }
            }

            // Configure dual wide camera systems
            else if device.deviceType == .builtInDualWideCamera {
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                if #available(iOS 15.0, *) {
                    print("VideoRecorder: Dual wide camera auto switching behavior: \(device.primaryConstituentDeviceSwitchingBehavior.rawValue)")
                }
            }

            // Configure dual camera systems
            else if device.deviceType == .builtInDualCamera {
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                if #available(iOS 15.0, *) {
                    print("VideoRecorder: Dual camera auto switching behavior: \(device.primaryConstituentDeviceSwitchingBehavior.rawValue)")
                }
            }

            // Configure standard wide angle camera
            else if device.deviceType == .builtInWideAngleCamera {
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                print("VideoRecorder: Configured standard wide angle camera")
            }

            device.unlockForConfiguration()
            print("VideoRecorder: Device configuration completed successfully")
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
     * Retry session startup specifically for iPhone 16 Pro triple camera issues
     */
    func retrySessionStartupForIPhone16Pro() {
        print("VideoRecorder: Attempting iPhone 16 Pro session recovery...")

        guard let session = self.captureSession else { return }

        // Stop current session if running
        if session.isRunning {
            session.stopRunning()
        }

        // Try different session presets for iPhone 16 Pro compatibility
        let fallbackPresets: [AVCaptureSession.Preset] = [
            .medium,
            .low,
            .hd1280x720,
            .vga640x480
        ]

        session.beginConfiguration()

        for preset in fallbackPresets {
            if session.canSetSessionPreset(preset) {
                session.sessionPreset = preset
                print("VideoRecorder: Trying fallback preset for iPhone 16 Pro: \(preset.rawValue)")
                break
            }
        }

        // For iPhone 16 Pro triple camera, try switching to standard wide angle first
        if let tripleCamera = self.backCamera, tripleCamera.deviceType == .builtInTripleCamera {
            print("VideoRecorder: iPhone 16 Pro detected - attempting wide angle fallback")

            // Look for a standard wide angle camera as fallback
            let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera],
                mediaType: .video,
                position: .back
            )

            if let wideAngleCamera = deviceDiscoverySession.devices.first {
                do {
                    // Remove current camera input
                    if let currentInput = self.cameraInput {
                        session.removeInput(currentInput)
                    }

                    // Add wide angle camera input
                    let wideAngleInput = try AVCaptureDeviceInput(device: wideAngleCamera)
                    if session.canAddInput(wideAngleInput) {
                        session.addInput(wideAngleInput)
                        self.cameraInput = wideAngleInput
                        print("VideoRecorder: Switched to wide angle camera for iPhone 16 Pro compatibility")
                    }
                } catch {
                    print("VideoRecorder: Failed to switch to wide angle camera: \(error)")
                    // Revert to original triple camera
                    if let originalInput = self.cameraInput, session.canAddInput(originalInput) {
                        session.addInput(originalInput)
                    }
                }
            }
        }

        session.commitConfiguration()

        // Try starting session again after configuration changes
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if session.isRunning {
                    print("VideoRecorder: iPhone 16 Pro session recovery successful!")
                } else {
                    print("VideoRecorder: iPhone 16 Pro session recovery failed")

                    // Last resort: try without any preset
                    session.beginConfiguration()
                    session.sessionPreset = .inputPriority
                    session.commitConfiguration()

                    DispatchQueue.global(qos: .userInitiated).async {
                        session.startRunning()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            if session.isRunning {
                                print("VideoRecorder: iPhone 16 Pro session started with inputPriority preset")
                            } else {
                                print("VideoRecorder: CRITICAL - iPhone 16 Pro session startup completely failed")
                            }
                        }
                    }
                }
            }
        }
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
                self.cameraView.isHidden = false
                print("VideoRecorder: Preview frame shown")
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
                self.cameraView.isHidden = true
                print("VideoRecorder: Preview frame hidden")
                call.resolve()
            }
        }
    }

    func initializeCameraView() {
        self.cameraView = CameraView(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        self.cameraView.isHidden = true
        self.cameraView.autoresizingMask = [.flexibleWidth, .flexibleHeight];
        self.captureVideoPreviewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession!)

        // Ensure preview layer frame is properly set for iPhone 16 Pro
        self.captureVideoPreviewLayer?.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        self.captureVideoPreviewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill

        self.cameraView.addPreviewLayer(self.captureVideoPreviewLayer)

        self.cameraView.backgroundColor = UIColor.black
        self.cameraView.videoPreviewLayer?.masksToBounds = true
        self.cameraView.clipsToBounds = false
        self.cameraView.layer.backgroundColor = UIColor.clear.cgColor

        self.capWebView!.superview!.insertSubview(self.cameraView, belowSubview: self.capWebView!)

        self.updateCameraView(self.currentFrameConfig)

        // Force initial layout update for iPhone 16 Pro compatibility
        DispatchQueue.main.async {
            self.cameraView.setNeedsLayout()
            self.cameraView.layoutIfNeeded()
            print("VideoRecorder: Camera view initialized and laid out")
        }
    }

    func updateCameraView(_ config: FrameConfig) {
        // Set position and dimensions
        let width = config.width as? String == "fill" ? UIScreen.main.bounds.width : config.width as! CGFloat
        let height = config.height as? String == "fill" ? UIScreen.main.bounds.height : config.height as! CGFloat
        self.cameraView.frame = CGRect(x: config.x, y: config.y, width: width, height: height)

        // Update preview layer frame to match camera view bounds
        self.cameraView.videoPreviewLayer?.frame = self.cameraView.bounds

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

        print("VideoRecorder: Camera view updated - Frame: \(self.cameraView.frame), Hidden: \(self.cameraView.isHidden)")
    }

    func refreshCameraPreview() {
        DispatchQueue.main.async {
            // Force refresh the preview layer to handle iPhone 16 Pro display issues
            if let previewLayer = self.cameraView?.videoPreviewLayer {
                previewLayer.setNeedsLayout()
                previewLayer.layoutIfNeeded()

                // Ensure the connection is properly configured for iPhone 16 Pro
                if let connection = previewLayer.connection {
                    connection.isEnabled = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        connection.isEnabled = true
                        print("VideoRecorder: Preview connection re-enabled")
                    }
                }

                // Force frame update
                previewLayer.frame = self.cameraView?.bounds ?? CGRect.zero
                print("VideoRecorder: Preview layer refreshed - Frame: \(previewLayer.frame)")
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
