import AVFoundation
import AVKit
import SwiftUI
import UIKit

enum FixedCameraLens: Int, CaseIterable {
    case ultraWide
    case wide
    case wideTwoX
    case teleFiveX

    var label: String {
        switch self {
        case .ultraWide:
            return "0.5"
        case .wide:
            return "1"
        case .wideTwoX:
            return "2"
        case .teleFiveX:
            return "5"
        }
    }

    var displayName: String {
        switch self {
        case .ultraWide:
            return "0.5x Ultra Wide"
        case .wide:
            return "1x Wide"
        case .wideTwoX:
            return "2x Wide Crop"
        case .teleFiveX:
            return "5x Telephoto"
        }
    }
}

struct FixedLensCameraRecorder: UIViewControllerRepresentable {
    let onComplete: (URL?) -> Void

    func makeUIViewController(context: Context) -> FixedLensCameraViewController {
        FixedLensCameraViewController(captureMode: .fixedLens, onComplete: onComplete)
    }

    func updateUIViewController(_ uiViewController: FixedLensCameraViewController, context: Context) {}
}

struct ExternalUSBCameraRecorder: UIViewControllerRepresentable {
    let settings: USBVideoCaptureSettings
    let onComplete: (URL?) -> Void

    func makeUIViewController(context: Context) -> FixedLensCameraViewController {
        FixedLensCameraViewController(captureMode: .externalUSB(settings), onComplete: onComplete)
    }

    func updateUIViewController(_ uiViewController: FixedLensCameraViewController, context: Context) {}
}

struct USBVideoCaptureSettings: Equatable {
    let deviceUniqueID: String
    let deviceName: String
    let formatID: String
    let formatLabel: String
    let framesPerSecond: Double

    var statusLabel: String {
        "\(deviceName) · \(formatLabel) · \(Self.fpsLabel(framesPerSecond))"
    }

    private static func fpsLabel(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.01 {
            return "\(Int(value.rounded())) fps"
        }
        return String(format: "%.1f fps", value)
    }
}

final class FixedLensCameraViewController: UIViewController, AVCaptureFileOutputRecordingDelegate {
    fileprivate enum CaptureMode {
        case fixedLens
        case externalUSB(USBVideoCaptureSettings)
    }

    private let onComplete: (URL?) -> Void
    private let captureMode: CaptureMode
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "hnm.fixed-lens-camera.session")
    private let movieOutput = AVCaptureMovieFileOutput()
    private let previewView = UIView()
    private let lensControl = UISegmentedControl(items: FixedCameraLens.allCases.map(\.label))
    private let recordButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var selectedLens: FixedCameraLens = .wide
    private var outputURL: URL?
    private var isConfigured = false
    private var captureEventInteraction: UIInteraction?

    fileprivate init(captureMode: CaptureMode, onComplete: @escaping (URL?) -> Void) {
        self.captureMode = captureMode
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureChrome()
        configurePreview()
        configureShortcuts()
        requestCameraAccess()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = previewView.bounds
    }

    private func configurePreview() {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        previewView.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
    }

    private func configureChrome() {
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.backgroundColor = .black
        previewView.layer.cornerRadius = 18
        previewView.layer.masksToBounds = true

        lensControl.translatesAutoresizingMaskIntoConstraints = false
        lensControl.selectedSegmentIndex = selectedLens.rawValue
        lensControl.selectedSegmentTintColor = .systemCyan
        lensControl.addTarget(self, action: #selector(lensChanged), for: .valueChanged)
        lensControl.isHidden = isExternalUSB

        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.setImage(UIImage(systemName: "record.circle.fill"), for: .normal)
        recordButton.tintColor = .systemRed
        recordButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 56, weight: .semibold),
            forImageIn: .normal
        )
        recordButton.addTarget(self, action: #selector(toggleRecording), for: .touchUpInside)

        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        cancelButton.tintColor = .white
        cancelButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold),
            forImageIn: .normal
        )
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = isExternalUSB ? "USB camera capture" : "Lens locked: \(selectedLens.displayName)"
        statusLabel.textColor = .white
        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2

        view.addSubview(previewView)
        view.addSubview(lensControl)
        view.addSubview(recordButton)
        view.addSubview(cancelButton)
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            cancelButton.widthAnchor.constraint(equalToConstant: 44),
            cancelButton.heightAnchor.constraint(equalToConstant: 44),

            lensControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            lensControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            lensControl.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.58),

            recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            recordButton.widthAnchor.constraint(equalToConstant: 72),
            recordButton.heightAnchor.constraint(equalToConstant: 72),

            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            statusLabel.bottomAnchor.constraint(equalTo: recordButton.topAnchor, constant: -18)
        ])
    }

    private func configureShortcuts() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(toggleRecording))
        tapGesture.cancelsTouchesInView = false
        previewView.addGestureRecognizer(tapGesture)

        if #available(iOS 17.2, *) {
            let interaction = AVCaptureEventInteraction { [weak self] event in
                guard event.phase == .ended else { return }
                self?.toggleRecording()
            }
            view.addInteraction(interaction)
            captureEventInteraction = interaction
        }
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: " ", modifierFlags: [], action: #selector(toggleRecording), discoverabilityTitle: "Start or stop recording"),
            UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(toggleRecording), discoverabilityTitle: "Start or stop recording"),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(cancel), discoverabilityTitle: "Cancel capture")
        ]
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    private func requestCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureSession()
                    } else {
                        self?.statusLabel.text = "Camera permission is required."
                    }
                }
            }
        default:
            statusLabel.text = "Camera permission is required."
        }
    }

    private func configureSession(for lens: FixedCameraLens? = nil) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = self.isExternalUSB ? .inputPriority : .high

            for input in self.session.inputs {
                self.session.removeInput(input)
            }

            do {
                let selection = try self.videoDevice(for: lens ?? self.selectedLens)
                let videoInput = try AVCaptureDeviceInput(device: selection.device)
                if self.session.canAddInput(videoInput) {
                    self.session.addInput(videoInput)
                }

                if !self.isExternalUSB, let audioDevice = AVCaptureDevice.default(for: .audio) {
                    let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                    if self.session.canAddInput(audioInput) {
                        self.session.addInput(audioInput)
                    }
                }

                if !self.session.outputs.contains(self.movieOutput), self.session.canAddOutput(self.movieOutput) {
                    self.session.addOutput(self.movieOutput)
                }
                if self.isExternalUSB {
                    self.movieOutput.connection(with: .video)?.preferredVideoStabilizationMode = .off
                    self.movieOutput.movieFragmentInterval = CMTime(seconds: 1, preferredTimescale: 600)
                }

                self.session.commitConfiguration()
                if !self.isExternalUSB {
                    self.lockZoom(selection.zoomFactor, on: selection.device)
                }
                self.isConfigured = true
                if !self.session.isRunning {
                    self.session.startRunning()
                }

                DispatchQueue.main.async {
                    self.statusLabel.text = "\(selection.status)\nTap preview or Space."
                }
            } catch {
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.statusLabel.text = error.localizedDescription
                }
            }
        }
    }

    private var isExternalUSB: Bool {
        if case .externalUSB = captureMode {
            return true
        }
        return false
    }

    private func videoDevice(for lens: FixedCameraLens) throws -> (device: AVCaptureDevice, zoomFactor: CGFloat, status: String) {
        if case .externalUSB(let settings) = captureMode {
            return try Self.externalVideoDevice(settings: settings)
        }
        return Self.fixedLensVideoDevice(for: lens)
    }

    private static func externalVideoDevice(settings: USBVideoCaptureSettings) throws -> (device: AVCaptureDevice, zoomFactor: CGFloat, status: String) {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .video,
            position: .unspecified
        )
        guard let device = discovery.devices.first(where: { $0.uniqueID == settings.deviceUniqueID }) ?? discovery.devices.first else {
            throw CameraCaptureError.noExternalCamera
        }
        try applyUSBSettings(settings, to: device)
        return (device, 1.0, "USB locked: \(settings.statusLabel)")
    }

    private static func applyUSBSettings(_ settings: USBVideoCaptureSettings, to device: AVCaptureDevice) throws {
        guard let format = device.formats.first(where: { CameraFormatSummary(format: $0).id == settings.formatID }) else {
            throw CameraCaptureError.usbFormatUnavailable
        }

        let fpsIsSupported = format.videoSupportedFrameRateRanges.contains { range in
            settings.framesPerSecond >= range.minFrameRate - 0.01 &&
            settings.framesPerSecond <= range.maxFrameRate + 0.01
        }
        guard fpsIsSupported else {
            throw CameraCaptureError.usbFrameRateUnavailable
        }

        try device.lockForConfiguration()
        device.activeFormat = format
        let frameDuration = CMTime(value: 1_000_000, timescale: CMTimeScale((settings.framesPerSecond * 1_000_000).rounded()))
        device.activeVideoMinFrameDuration = frameDuration
        device.activeVideoMaxFrameDuration = frameDuration

        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
        if device.isLowLightBoostSupported {
            device.automaticallyEnablesLowLightBoostWhenAvailable = false
        }
        device.unlockForConfiguration()
    }

    private static func fixedLensVideoDevice(for lens: FixedCameraLens) -> (device: AVCaptureDevice, zoomFactor: CGFloat, status: String) {
        let wide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)

        switch lens {
        case .ultraWide:
            if let device = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) {
                return (device, 1.0, "Lens locked: 0.5x Ultra Wide")
            }
            return (wide!, 1.0, "0.5x unavailable. Fallback locked: 1x Wide")
        case .wide:
            return (wide!, 1.0, "Lens locked: 1x Wide")
        case .wideTwoX:
            return (wide!, 2.0, "Lens locked: 2x Wide Crop")
        case .teleFiveX:
            if let device = AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back) {
                return (device, 1.0, "Lens locked: 5x Telephoto")
            }
            return (wide!, 5.0, "5x telephoto unavailable. Fallback locked: 5x digital crop")
        }
    }

    private func lockZoom(_ zoom: CGFloat, on device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.deviceType != .external {
                device.videoZoomFactor = min(max(zoom, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
            }
            device.unlockForConfiguration()
        } catch {
            DispatchQueue.main.async {
                self.statusLabel.text = "Lens selected, zoom lock failed."
            }
        }
    }

    @objc private func lensChanged() {
        guard case .fixedLens = captureMode else { return }
        guard let lens = FixedCameraLens(rawValue: lensControl.selectedSegmentIndex) else { return }
        selectedLens = lens
        configureSession(for: lens)
    }

    @objc private func toggleRecording() {
        if movieOutput.isRecording {
            movieOutput.stopRecording()
            return
        }
        guard isConfigured else {
            statusLabel.text = "Camera is not ready."
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hnm-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        outputURL = url
        movieOutput.startRecording(to: url, recordingDelegate: self)
        recordButton.tintColor = .white
        let source: String
        if case .externalUSB(let settings) = captureMode {
            source = settings.statusLabel
        } else {
            source = selectedLens.displayName
        }
        statusLabel.text = "Recording with \(source)\nTap preview, Space, or Camera Control to stop."
    }

    @objc private func cancel() {
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
        dismiss(animated: true) { [onComplete] in
            onComplete(nil)
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
        DispatchQueue.main.async { [self] in
            self.recordButton.tintColor = .systemRed
            self.dismiss(animated: true) { [onComplete] in
                onComplete(error == nil ? outputFileURL : nil)
            }
        }
    }
}

private enum CameraCaptureError: LocalizedError {
    case noExternalCamera
    case usbFormatUnavailable
    case usbFrameRateUnavailable

    var errorDescription: String? {
        switch self {
        case .noExternalCamera:
            return "No USB camera detected. Connect a UVC camera and try again."
        case .usbFormatUnavailable:
            return "The selected USB camera format is no longer available."
        case .usbFrameRateUnavailable:
            return "The selected USB camera frame rate is not supported by this format."
        }
    }
}
