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

struct CameraDeviceParametersCard: View {
    let device: CameraDeviceSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
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
                ParameterRow(label: "FPS", value: device.frameRates)
                ParameterRow(label: "Format count", value: "\(device.formatCount)")
            }
        }
        .padding(.vertical, 6)
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
    let formatCount: Int
    let isExternal: Bool

    init(device: AVCaptureDevice) {
        id = device.uniqueID
        name = device.localizedName
        type = device.deviceType.rawValue.replacingOccurrences(of: "AVCaptureDeviceType", with: "")
        position = Self.positionLabel(device.position)
        uniqueID = device.uniqueID
        activeFormat = Self.formatLabel(device.activeFormat)
        frameRates = Self.frameRateLabel(device.activeFormat.videoSupportedFrameRateRanges)
        formatCount = device.formats.count
        isExternal = device.deviceType == .external
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
