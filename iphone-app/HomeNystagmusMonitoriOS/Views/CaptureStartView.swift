import AVFoundation
import SwiftUI

struct HeaderView: View {
    let isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
            HStack(spacing: 10) {
                Image(systemName: "eye.trianglebadge.exclamationmark.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.cyan, .orange)
                    .font(.system(size: isCompact ? 26 : 30, weight: .semibold))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Home Nystagmus Monitor")
                        .font((isCompact ? Font.title3 : Font.title2).weight(.bold))
                        .foregroundStyle(.primary)
                    Text("iPhone device prototype")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if !isCompact {
                Text("Capture or import a short eye video. The prototype presents a demo-ready nystagmus dashboard.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CaptureStartView: View {
    let isAnalyzing: Bool
    let errorMessage: String?
    let isCompact: Bool
    let onStartCamera: () -> Void
    let onStartUSBCamera: () -> Void
    let onImportVideo: () -> Void
    let onUSBCamera: () -> Void
    let onShowPrinciple: () -> Void

    var body: some View {
        VStack(spacing: isCompact ? 10 : 12) {
            CameraStageCard(isCompact: isCompact)

            VStack(spacing: 8) {
                Button(action: onStartCamera) {
                    Label("Start Capture", systemImage: "video.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(isAnalyzing)

                Button(action: onStartUSBCamera) {
                    Label("USB Capture", systemImage: "cable.connector.video")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .disabled(isAnalyzing)

                Button(action: onImportVideo) {
                    Label("Import Video", systemImage: "square.and.arrow.down.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .disabled(isAnalyzing)
            }

            USBCameraSection(isCompact: isCompact, isDisabled: isAnalyzing, onOpen: onUSBCamera)
            PrincipleFigureSection(isCompact: isCompact, isDisabled: isAnalyzing, onOpen: onShowPrinciple)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

struct CameraStageCard: View {
    let isCompact: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.black.gradient)
                .frame(height: isCompact ? 230 : 285)

            VStack(spacing: isCompact ? 12 : 14) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.18), lineWidth: isCompact ? 18 : 22)
                        .frame(width: isCompact ? 112 : 132, height: isCompact ? 112 : 132)
                    Circle()
                        .stroke(.cyan.opacity(0.78), lineWidth: 3)
                        .frame(width: isCompact ? 88 : 104, height: isCompact ? 88 : 104)
                    Image(systemName: "eye.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .font(.system(size: isCompact ? 36 : 42, weight: .semibold))
                }

                VStack(spacing: 5) {
                    Text("Align one eye in frame")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Keep the device steady for 10 to 15 seconds.")
                        .font(isCompact ? .footnote : .subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .padding(isCompact ? 18 : 22)
        }
    }
}

struct PrincipleFigureSection: View {
    let isCompact: Bool
    let isDisabled: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: isCompact ? 18 : 20, weight: .semibold))
                    .foregroundStyle(.cyan)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Principle Figure")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("Scientific cover-style overview of capture, ROI, gaze signal, and pattern analysis.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(isCompact ? 10 : 12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

struct PrincipleFigureView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image("HomeNystagmusPrinciple")
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.24), radius: 18, y: 10)
                    .accessibilityLabel("Scientific overview of the Home Nystagmus Monitor workflow")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Home Nystagmus Monitor")
                        .font(.title3.weight(.bold))
                    Text("A prototype explanation figure for the optical clip-on capture workflow and local nystagmus pattern analysis.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
        }
        .background(AppBackground())
        .navigationTitle("Principle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

struct USBCameraSection: View {
    let isCompact: Bool
    let isDisabled: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(systemName: "cable.connector")
                    .font(.system(size: isCompact ? 17 : 19, weight: .semibold))
                    .foregroundStyle(.cyan)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("USB camera")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("Detect external camera parameters before face capture.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(isCompact ? 10 : 12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

struct USBCameraParametersView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var devices: [CameraDeviceSummary] = []
    @State private var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        List {
            Section {
                HStack {
                    Label("Video permission", systemImage: "lock.shield")
                    Spacer()
                    Text(permissionLabel)
                        .foregroundStyle(permissionColor)
                        .font(.subheadline.weight(.semibold))
                }

                Button {
                    detectDevices()
                } label: {
                    Label("Refresh Detection", systemImage: "arrow.clockwise")
                }
            }

            Section("Detected cameras") {
                if devices.isEmpty {
                    ContentUnavailableView(
                        "No camera detected",
                        systemImage: "video.slash",
                        description: Text("Connect a USB/UVC camera and tap Refresh Detection. iOS only lists devices exposed through AVFoundation.")
                    )
                    .frame(minHeight: 180)
                } else {
                    ForEach(devices) { device in
                        CameraDeviceParametersCard(device: device)
                    }
                }
            }
        }
        .navigationTitle("USB camera")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task {
            await requestAccessIfNeeded()
            detectDevices()
        }
    }

    private var permissionLabel: String {
        switch authorizationStatus {
        case .authorized:
            return "Granted"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not requested"
        @unknown default:
            return "Unknown"
        }
    }

    private var permissionColor: Color {
        authorizationStatus == .authorized ? .green : .orange
    }

    private func requestAccessIfNeeded() async {
        guard authorizationStatus == .notDetermined else { return }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        authorizationStatus = granted ? .authorized : AVCaptureDevice.authorizationStatus(for: .video)
    }

    private func detectDevices() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera, .builtInTrueDepthCamera],
            mediaType: .video,
            position: .unspecified
        )
        devices = session.devices.map(CameraDeviceSummary.init(device:))
    }
}

struct USBCameraCaptureSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var devices: [CameraDeviceSummary] = []
    @State private var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var selectedDeviceID = ""
    @State private var selectedFormatID = ""
    @State private var selectedFPS = 0.0
    let onStart: (USBVideoCaptureSettings) -> Void

    var body: some View {
        List {
            Section {
                HStack {
                    Label("Video permission", systemImage: "lock.shield")
                    Spacer()
                    Text(permissionLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(authorizationStatus == .authorized ? .green : .orange)
                }

                Button {
                    detectDevices()
                } label: {
                    Label("Refresh USB Cameras", systemImage: "arrow.clockwise")
                }
            }

            if devices.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No USB camera detected",
                        systemImage: "cable.connector.slash",
                        description: Text("Connect a UVC camera and refresh. iPadOS must expose it through AVFoundation.")
                    )
                    .frame(minHeight: 220)
                }
            } else {
                Section("Camera") {
                    Picker("Device", selection: $selectedDeviceID) {
                        ForEach(devices) { device in
                            Text(device.name).tag(device.id)
                        }
                    }
                    .onChange(of: selectedDeviceID) { _, _ in
                        selectDefaultFormat()
                    }
                }

                if let selectedDevice {
                    Section("Capture format") {
                        Picker("Format", selection: $selectedFormatID) {
                            ForEach(selectedDevice.supportedFormats) { format in
                                Text(format.displayLabel).tag(format.id)
                            }
                        }
                        .onChange(of: selectedFormatID) { _, _ in
                            selectDefaultFPS()
                        }

                        if let selectedFormat {
                            Picker("Frame rate", selection: $selectedFPS) {
                                ForEach(selectedFormat.frameRateOptions, id: \.self) { fps in
                                    Text(fpsLabel(fps)).tag(fps)
                                }
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Requested capture")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                Text("\(selectedDevice.name) · \(selectedFormat.displayLabel) · \(fpsLabel(selectedFPS))")
                                    .font(.caption)
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    Section {
                        Button {
                            guard let selectedFormat else { return }
                            onStart(
                                USBVideoCaptureSettings(
                                    deviceUniqueID: selectedDevice.uniqueID,
                                    deviceName: selectedDevice.name,
                                    formatID: selectedFormat.id,
                                    formatLabel: selectedFormat.displayLabel,
                                    framesPerSecond: selectedFPS
                                )
                            )
                        } label: {
                            Label("Start USB Capture", systemImage: "record.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(selectedFormat == nil || selectedFPS <= 0)
                    }
                }
            }
        }
        .navigationTitle("USB Capture")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .task {
            await requestAccessIfNeeded()
            detectDevices()
        }
    }

    private var selectedDevice: CameraDeviceSummary? {
        devices.first(where: { $0.id == selectedDeviceID })
    }

    private var selectedFormat: CameraFormatSummary? {
        selectedDevice?.supportedFormats.first(where: { $0.id == selectedFormatID })
    }

    private var permissionLabel: String {
        switch authorizationStatus {
        case .authorized:
            return "Granted"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not requested"
        @unknown default:
            return "Unknown"
        }
    }

    private func requestAccessIfNeeded() async {
        guard authorizationStatus == .notDetermined else { return }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        authorizationStatus = granted ? .authorized : AVCaptureDevice.authorizationStatus(for: .video)
    }

    private func detectDevices() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .video,
            position: .unspecified
        )
        devices = session.devices.map(CameraDeviceSummary.init(device:))
        if !devices.contains(where: { $0.id == selectedDeviceID }) {
            selectedDeviceID = devices.first?.id ?? ""
        }
        selectDefaultFormat()
    }

    private func selectDefaultFormat() {
        guard let selectedDevice else {
            selectedFormatID = ""
            selectedFPS = 0
            return
        }
        if !selectedDevice.supportedFormats.contains(where: { $0.id == selectedFormatID }) {
            selectedFormatID = selectedDevice.supportedFormats.first?.id ?? ""
        }
        selectDefaultFPS()
    }

    private func selectDefaultFPS() {
        guard let selectedFormat else {
            selectedFPS = 0
            return
        }
        if !selectedFormat.frameRateOptions.contains(where: { abs($0 - selectedFPS) < 0.01 }) {
            selectedFPS = selectedFormat.frameRateOptions.first ?? selectedFormat.maximumFrameRate
        }
    }

    private func fpsLabel(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.01 {
            return "\(Int(value.rounded())) fps"
        }
        return String(format: "%.1f fps", value)
    }
}

struct CameraDeviceParametersCard: View {
    let device: CameraDeviceSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(device.name)
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
                Text(device.isExternal ? "USB / External" : device.position)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(device.isExternal ? .cyan : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((device.isExternal ? Color.cyan : Color.secondary).opacity(0.12), in: Capsule())
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                ParameterRow(label: "Type", value: device.type)
                ParameterRow(label: "Unique ID", value: device.uniqueID)
                ParameterRow(label: "Active format", value: device.activeFormat)
                ParameterRow(label: "Active FPS", value: device.frameRates)
                ParameterRow(label: "Best mode", value: device.bestMode)
                ParameterRow(label: "Format count", value: "\(device.formatCount)")
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Adjustable parameters")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(device.adjustableParameters.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(device.supportedFormats) { format in
                        CameraFormatRow(format: format)
                    }
                }
                .padding(.top, 6)
            } label: {
                Label("All supported formats", systemImage: "list.bullet.rectangle")
                    .font(.caption.weight(.bold))
            }
        }
        .padding(.vertical, 6)
    }
}

struct CameraFormatRow: View {
    let format: CameraFormatSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(format.resolution)
                    .font(.caption.weight(.bold))
                Text(format.codec)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.12), in: Capsule())
                if format.supportsHighSpeed {
                    Text("HIGH FPS")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.cyan.opacity(0.12), in: Capsule())
                }
                Spacer(minLength: 0)
            }

            Text(format.frameRates)
                .font(.caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)

            Text(format.sensorParameters)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(8)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ParameterRow: View {
    let label: String
    let value: String

    var body: some View {
        GridRow {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }
}

struct CameraDeviceSummary: Identifiable {
    let id: String
    let name: String
    let type: String
    let position: String
    let uniqueID: String
    let activeFormat: String
    let frameRates: String
    let bestMode: String
    let formatCount: Int
    let isExternal: Bool
    let adjustableParameters: [String]
    let supportedFormats: [CameraFormatSummary]

    init(device: AVCaptureDevice) {
        let formats = device.formats.map(CameraFormatSummary.init(format:))
        id = device.uniqueID
        name = device.localizedName
        type = device.deviceType.rawValue.replacingOccurrences(of: "AVCaptureDeviceType", with: "")
        position = Self.positionLabel(device.position)
        uniqueID = device.uniqueID
        activeFormat = Self.formatLabel(device.activeFormat)
        frameRates = Self.frameRateLabel(device.activeFormat.videoSupportedFrameRateRanges)
        formatCount = device.formats.count
        isExternal = device.deviceType == .external
        supportedFormats = formats.sorted(by: CameraFormatSummary.sortPriority)
        bestMode = supportedFormats.first?.displayLabel ?? "Unknown"
        adjustableParameters = Self.adjustableParameterLabels(device: device, formats: formats)
    }

    private static func positionLabel(_ position: AVCaptureDevice.Position) -> String {
        switch position {
        case .front:
            return "Front"
        case .back:
            return "Back"
        case .unspecified:
            return "Unspecified"
        @unknown default:
            return "Unknown"
        }
    }

    private static func formatLabel(_ format: AVCaptureDevice.Format) -> String {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let subtype = CMFormatDescriptionGetMediaSubType(format.formatDescription)
        return "\(dimensions.width)x\(dimensions.height) · \(fourCC(subtype))"
    }

    private static func frameRateLabel(_ ranges: [AVFrameRateRange]) -> String {
        guard !ranges.isEmpty else { return "Unknown" }
        return ranges
            .map { range in
                if abs(range.minFrameRate - range.maxFrameRate) < 0.01 {
                    return "\(Int(range.maxFrameRate.rounded())) fps"
                }
                return "\(Int(range.minFrameRate.rounded()))-\(Int(range.maxFrameRate.rounded())) fps"
            }
            .joined(separator: ", ")
    }

    private static func adjustableParameterLabels(device: AVCaptureDevice, formats: [CameraFormatSummary]) -> [String] {
        var labels: [String] = []

        if device.isFocusModeSupported(.locked) || device.isFocusModeSupported(.autoFocus) || device.isFocusModeSupported(.continuousAutoFocus) {
            labels.append("Focus")
        }
        if device.isExposureModeSupported(.locked) || device.isExposureModeSupported(.autoExpose) || device.isExposureModeSupported(.continuousAutoExposure) || device.isExposureModeSupported(.custom) {
            labels.append("Exposure")
        }
        if device.isWhiteBalanceModeSupported(.locked) || device.isWhiteBalanceModeSupported(.autoWhiteBalance) || device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            labels.append("White balance")
        }
        if device.hasTorch {
            labels.append("Torch")
        }
        if device.maxAvailableVideoZoomFactor > device.minAvailableVideoZoomFactor {
            labels.append("Zoom \(Self.compactNumber(device.minAvailableVideoZoomFactor))-\(Self.compactNumber(device.maxAvailableVideoZoomFactor))x")
        }
        if device.isLowLightBoostSupported {
            labels.append("Low light boost")
        }
        if formats.contains(where: { $0.maximumFrameRate >= 120 }) {
            labels.append("120 fps mode")
        }

        return labels.isEmpty ? ["No adjustable controls exposed by AVFoundation"] : labels
    }

    private static func fourCC(_ value: FourCharCode) -> String {
        let chars: [UInt8] = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        let string = String(bytes: chars, encoding: .macOSRoman) ?? "\(value)"
        return string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func compactNumber(_ value: CGFloat) -> String {
        if abs(value.rounded() - value) < 0.01 {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.1f", Double(value))
    }
}

struct CameraFormatSummary: Identifiable {
    let id: String
    let width: Int32
    let height: Int32
    let codec: String
    let frameRates: String
    let frameRateOptions: [Double]
    let maximumFrameRate: Double
    let isoRange: String
    let exposureRange: String

    var resolution: String {
        "\(width)x\(height)"
    }

    var displayLabel: String {
        "\(resolution) · up to \(Int(maximumFrameRate.rounded())) fps · \(codec)"
    }

    var supportsHighSpeed: Bool {
        maximumFrameRate >= 120
    }

    var sensorParameters: String {
        "ISO \(isoRange) · exposure \(exposureRange)"
    }

    init(format: AVCaptureDevice.Format) {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let subtype = CMFormatDescriptionGetMediaSubType(format.formatDescription)
        let ranges = format.videoSupportedFrameRateRanges

        width = dimensions.width
        height = dimensions.height
        codec = Self.fourCC(subtype)
        frameRates = Self.frameRateLabel(ranges)
        frameRateOptions = Self.frameRateOptions(ranges)
        maximumFrameRate = ranges.map(\.maxFrameRate).max() ?? 0
        isoRange = "\(Self.compactNumber(format.minISO))-\(Self.compactNumber(format.maxISO))"
        exposureRange = "\(Self.durationLabel(format.minExposureDuration))-\(Self.durationLabel(format.maxExposureDuration))"
        id = "\(width)x\(height)-\(codec)-\(frameRates)-\(isoRange)-\(exposureRange)"
    }

    static func sortPriority(lhs: CameraFormatSummary, rhs: CameraFormatSummary) -> Bool {
        if lhs.maximumFrameRate != rhs.maximumFrameRate {
            return lhs.maximumFrameRate > rhs.maximumFrameRate
        }
        let lhsPixels = lhs.width * lhs.height
        let rhsPixels = rhs.width * rhs.height
        if lhsPixels != rhsPixels {
            return lhsPixels > rhsPixels
        }
        return lhs.codec < rhs.codec
    }

    private static func frameRateLabel(_ ranges: [AVFrameRateRange]) -> String {
        guard !ranges.isEmpty else { return "Unknown fps" }
        return ranges
            .map { range in
                if abs(range.minFrameRate - range.maxFrameRate) < 0.01 {
                    return "\(compactNumber(range.maxFrameRate)) fps"
                }
                return "\(compactNumber(range.minFrameRate))-\(compactNumber(range.maxFrameRate)) fps"
            }
            .joined(separator: ", ")
    }

    private static func frameRateOptions(_ ranges: [AVFrameRateRange]) -> [Double] {
        let commonRates = [240.0, 180.0, 120.0, 90.0, 60.0, 30.0, 24.0]
        var values: [Double] = ranges.flatMap { range in
            var candidates = [range.maxFrameRate, range.minFrameRate]
            candidates.append(contentsOf: commonRates.filter { rate in
                rate >= range.minFrameRate - 0.01 && rate <= range.maxFrameRate + 0.01
            })
            return candidates
        }

        values = values
            .filter { $0.isFinite && $0 > 0 }
            .map { ($0 * 100).rounded() / 100 }
            .sorted(by: >)

        return values.reduce(into: []) { partial, value in
            if !partial.contains(where: { abs($0 - value) < 0.01 }) {
                partial.append(value)
            }
        }
    }

    private static func durationLabel(_ duration: CMTime) -> String {
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else { return "unknown" }
        if seconds < 0.001 {
            return "1/\(Int((1 / seconds).rounded()))s"
        }
        return "\(compactNumber(seconds * 1000))ms"
    }

    private static func compactNumber(_ value: Float) -> String {
        compactNumber(Double(value))
    }

    private static func compactNumber(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.01 {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.1f", value)
    }

    private static func fourCC(_ value: FourCharCode) -> String {
        let chars: [UInt8] = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        let string = String(bytes: chars, encoding: .macOSRoman) ?? "\(value)"
        return string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
