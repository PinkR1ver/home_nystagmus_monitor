import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

enum CaptureMode: String, CaseIterable, Identifiable {
  case camera
  case video

  var id: Self { self }
  var title: String { self == .camera ? "实时双摄" : "视频复盘" }
  var symbol: String { self == .camera ? "camera.aperture" : "play.rectangle" }
}

struct ContentView: View {
  @StateObject private var camera = CameraManager()
  @StateObject private var capture = DualSignalCapture()
  @StateObject private var video = VideoSource()

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var mode: CaptureMode = .camera
  @State private var showPicker = false
  @State private var selectedItem: PhotosPickerItem?
  @State private var isAssessmentRunning = false
  @State private var sessionStartedAt: Date?
  @State private var showCompletion = false
  @State private var completionMessage = "正在保存本次三信号记录。"

  var body: some View {
    ZStack {
      preview
        .ignoresSafeArea()

      previewScrim
        .ignoresSafeArea()
        .allowsHitTesting(false)

      BodyGuideView(isTracking: capture.latestSignals?.personDetected == true)
        .padding(.horizontal, 54)
        .padding(.top, 128)
        .padding(.bottom, 310)
        .opacity(mode == .camera ? 1 : 0)
        .allowsHitTesting(false)

      VStack(spacing: 0) {
        header
          .padding(.horizontal, 20)
          .padding(.top, 10)

        HStack(alignment: .top) {
          sessionLabel
          Spacer()
          if mode == .camera && camera.isDualCameraActive {
            stereoDepthPreview
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)

        Spacer(minLength: 12)
        controlDeck
      }

      if let message = camera.errorMessage ?? capture.modelError {
        errorBanner(message)
      }
    }
    .background(Color.black)
    .onAppear(perform: connectPipelines)
    .onDisappear {
      camera.stop()
      video.stop()
    }
    .photosPicker(
      isPresented: $showPicker,
      selection: $selectedItem,
      matching: .videos
    )
    .onChange(of: selectedItem) { _, item in
      guard let item else { return }
      loadVideo(item)
    }
    .sensoryFeedback(.impact(weight: .medium), trigger: isAssessmentRunning)
    .sensoryFeedback(.success, trigger: showCompletion)
    .alert("训练采集完成", isPresented: $showCompletion) {
      Button("完成", role: .cancel) {}
    } message: {
      Text(completionMessage)
    }
  }

  @ViewBuilder
  private var preview: some View {
    if mode == .camera {
      CameraPreviewView(
        camera: camera,
        feed: .rear,
        signals: capture.latestSignals
      )
    } else if let image = video.currentImage {
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
        .clipped()
    } else {
      VideoEmptyState {
        showPicker = true
      }
    }
  }

  private var previewScrim: some View {
    VStack(spacing: 0) {
      LinearGradient(
        colors: [
          Color.black.opacity(0.72),
          Color.black.opacity(0.08),
          .clear,
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .frame(height: 240)

      Spacer()

      LinearGradient(
        colors: [.clear, Color.black.opacity(0.30)],
        startPoint: .top,
        endPoint: .bottom
      )
      .frame(height: 220)
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text("REHAB MOTION")
          .font(.caption2.weight(.bold))
          .tracking(1.6)
          .foregroundStyle(RehabPalette.mint)
        Text("三信号康复评估")
          .font(.title3.weight(.semibold))
          .foregroundStyle(.white)
      }

      Spacer()

      modelBadge
    }
    .accessibilityElement(children: .combine)
  }

  private var modelBadge: some View {
    HStack(spacing: 7) {
      Image(systemName: capture.modelError == nil ? "cpu.fill" : "exclamationmark.triangle.fill")
        .symbolRenderingMode(.hierarchical)
      Text(capture.modelStatus)
        .font(.caption.weight(.semibold))
        .lineLimit(1)
    }
    .foregroundStyle(capture.modelError == nil ? .white : Color.orange)
    .padding(.horizontal, 12)
    .frame(height: 36)
    .background(.thinMaterial, in: Capsule())
    .accessibilityLabel("分析模型：\(capture.modelStatus)")
  }

  private var sessionLabel: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 8) {
        Circle()
          .fill(isAssessmentRunning ? Color.red : RehabPalette.mint)
          .frame(width: 8, height: 8)
          .shadow(
            color: isAssessmentRunning ? .red.opacity(0.7) : RehabPalette.mint.opacity(0.7),
            radius: 5
          )
        Text(isAssessmentRunning ? "正在采集" : "训练 01 · 准备就绪")
          .font(.subheadline.weight(.semibold))
      }

      TimelineView(.periodic(from: .now, by: 1)) { context in
        Text(sessionDetail(at: context.date))
          .font(.caption.monospacedDigit())
          .foregroundStyle(.white.opacity(0.68))
      }
    }
    .foregroundStyle(.white)
  }

  private var stereoDepthPreview: some View {
    ZStack(alignment: .bottomLeading) {
      if let image = capture.depthPreviewImage {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        Color.black
          .overlay {
            ProgressView()
              .tint(.white)
          }
      }

      LinearGradient(
        colors: [.clear, .black.opacity(0.72)],
        startPoint: .center,
        endPoint: .bottom
      )

      Label("双后摄深度", systemImage: "cube.transparent")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white)
        .padding(9)
    }
    .frame(width: 116, height: 148)
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(.white.opacity(0.22), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.34), radius: 24, y: 12)
    .transition(
      reduceMotion
        ? .opacity
        : .scale(scale: 0.96, anchor: .topTrailing).combined(with: .opacity)
    )
    .accessibilityLabel("后置广角与超广角生成的立体深度画面")
  }

  private var controlDeck: some View {
    VStack(spacing: 0) {
      Capsule()
        .fill(.white.opacity(0.28))
        .frame(width: 38, height: 4)
        .padding(.top, 10)
        .padding(.bottom, 12)

      HStack {
        Label(
          camera.isDualCameraActive ? "立体双后摄" : "兼容模式",
          systemImage: camera.isDualCameraActive
            ? "camera.metering.multispot"
            : "camera"
        )
        .foregroundStyle(camera.isDualCameraActive ? RehabPalette.mint : .orange)

        Spacer()

        VStack(alignment: .trailing, spacing: 2) {
          Text(camera.statusText)
          Text(capture.performanceText)
            .font(.caption2.monospacedDigit())
        }
        .foregroundStyle(.secondary)
      }
      .font(.caption.weight(.semibold))
      .padding(.horizontal, 20)

      SignalPanelView(
        signals: capture.latestSignals,
        isReady: mode == .camera ? camera.isReady : video.isLoaded
      )
      .padding(.top, 15)

      Divider()
        .overlay(.white.opacity(0.08))
        .padding(.horizontal, 20)
        .padding(.top, 16)

      HStack(spacing: 18) {
        sourcePicker
        Spacer()
        secondaryAction
        primaryAction
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 16)
    }
    .background(.ultraThinMaterial)
    .clipShape(
      UnevenRoundedRectangle(
        topLeadingRadius: 30,
        topTrailingRadius: 30,
        style: .continuous
      )
    )
    .overlay(alignment: .top) {
      LinearGradient(
        colors: [.white.opacity(0.22), .white.opacity(0.02)],
        startPoint: .leading,
        endPoint: .trailing
      )
      .frame(height: 1)
    }
  }

  private var sourcePicker: some View {
    HStack(spacing: 3) {
      ForEach(CaptureMode.allCases) { item in
        Button {
          changeMode(to: item)
        } label: {
          Image(systemName: item.symbol)
            .symbolRenderingMode(.hierarchical)
            .frame(width: 42, height: 38)
            .foregroundStyle(mode == item ? .black : .white.opacity(0.66))
            .background(
              mode == item ? RehabPalette.mint : Color.clear,
              in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(item.title)
      }
    }
    .padding(3)
    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 15))
  }

  @ViewBuilder
  private var secondaryAction: some View {
    Button {
      showPicker = true
    } label: {
      Image(systemName: "square.and.arrow.down")
        .font(.body.weight(.semibold))
        .frame(width: 46, height: 46)
        .background(.white.opacity(0.10), in: Circle())
    }
    .buttonStyle(PressableButtonStyle())
    .foregroundStyle(.white)
    .accessibilityLabel("导入训练视频")
  }

  private var primaryAction: some View {
    Button(action: performPrimaryAction) {
      ZStack {
        Circle()
          .fill(isAssessmentRunning ? Color.white : RehabPalette.mint)
        Circle()
          .stroke(.white.opacity(0.30), lineWidth: 1)
          .padding(-5)

        Image(
          systemName: primaryActionSymbol
        )
        .font(.title3.weight(.bold))
        .foregroundStyle(isAssessmentRunning ? Color.red : Color.black)
        .contentTransition(.symbolEffect(.replace))
      }
      .frame(width: 56, height: 56)
    }
    .buttonStyle(PressableButtonStyle(scale: 0.94))
    .accessibilityLabel(primaryActionLabel)
  }

  private var primaryActionSymbol: String {
    if mode == .video {
      return video.isPlaying ? "pause.fill" : "play.fill"
    }
    return isAssessmentRunning ? "stop.fill" : "record.circle"
  }

  private var primaryActionLabel: String {
    if mode == .video {
      return video.isPlaying ? "暂停视频" : "播放视频"
    }
    return isAssessmentRunning ? "结束采集" : "开始采集"
  }

  private func sessionDetail(at date: Date) -> String {
    guard let sessionStartedAt, isAssessmentRunning else {
      return capture.latestSignals?.personDetected == true
        ? capture.processingStatus
        : "请站入取景框"
    }
    let elapsed = max(0, Int(date.timeIntervalSince(sessionStartedAt)))
    return String(
      format: "%02d:%02d  ·  立体人体 + 头动 + 眼动",
      elapsed / 60,
      elapsed % 60
    )
  }

  private func performPrimaryAction() {
    if mode == .video {
      if !video.isLoaded {
        showPicker = true
      } else if video.isPlaying {
        video.pause()
      } else {
        video.play()
      }
      return
    }

    if isAssessmentRunning {
      isAssessmentRunning = false
      sessionStartedAt = nil
      capture.stopRecording { result in
        switch result {
        case .success(let url):
          completionMessage =
            "已保存 \(capture.recordedSampleCount) 个三信号样本：\(url.lastPathComponent)"
        case .failure(let error):
          completionMessage = "采集已结束，但记录保存失败：\(error.localizedDescription)"
        }
        showCompletion = true
      }
    } else {
      sessionStartedAt = Date()
      isAssessmentRunning = true
      capture.startRecording()
    }
  }

  private func changeMode(to newMode: CaptureMode) {
    guard newMode != mode else { return }
    isAssessmentRunning = false
    sessionStartedAt = nil
    withAnimation(reduceMotion ? nil : .smooth(duration: 0.24)) {
      mode = newMode
    }

    if newMode == .camera {
      video.pause()
      camera.start()
    } else {
      camera.stop()
    }
  }

  private func connectPipelines() {
    camera.onStereoFrame = {
      capture.processStereoFrame($0, depthData: $1)
    }
    camera.onSingleFrame = { capture.processSingleFrame($0) }
    video.onFrame = { capture.processSingleFrame($0) }
  }

  private func loadVideo(_ item: PhotosPickerItem) {
    Task {
      do {
        guard
          let transfer = try await item.loadTransferable(
            type: TransferableVideo.self
          )
        else {
          return
        }
        await MainActor.run {
          video.load(url: transfer.url)
          changeMode(to: .video)
        }
      } catch {
        await MainActor.run {
          camera.errorMessage = "视频导入失败：\(error.localizedDescription)"
        }
      }
    }
  }

  private func errorBanner(_ message: String) -> some View {
    VStack {
      HStack(spacing: 10) {
        Image(systemName: "exclamationmark.triangle.fill")
          .symbolRenderingMode(.hierarchical)
        Text(message)
          .font(.footnote.weight(.medium))
          .lineLimit(2)
        Spacer(minLength: 0)
      }
      .foregroundStyle(.white)
      .padding(14)
      .background(Color.red.opacity(0.88), in: RoundedRectangle(cornerRadius: 16))
      .padding(.horizontal, 20)
      .padding(.top, 78)
      Spacer()
    }
    .transition(.move(edge: .top).combined(with: .opacity))
  }
}

private struct VideoEmptyState: View {
  let action: () -> Void

  var body: some View {
    Color(red: 0.055, green: 0.067, blue: 0.064)
      .overlay {
        VStack(alignment: .leading, spacing: 22) {
          Image(systemName: "waveform.path.ecg.rectangle")
            .font(.system(size: 38, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(RehabPalette.mint)

          VStack(alignment: .leading, spacing: 8) {
            Text("复盘一段训练视频")
              .font(.title2.weight(.semibold))
            Text("导入本地视频，离线提取人体姿态、头动与眼动信号。单视频不包含双后摄深度。")
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }

          Button("选择视频", action: action)
            .buttonStyle(.borderedProminent)
            .tint(RehabPalette.mint)
            .foregroundStyle(.black)
        }
        .frame(maxWidth: 320, alignment: .leading)
        .padding(28)
      }
  }
}

private struct BodyGuideView: View {
  let isTracking: Bool

  var body: some View {
    GeometryReader { proxy in
      Path { path in
        let length = min(proxy.size.width, proxy.size.height) * 0.12
        let width = proxy.size.width
        let height = proxy.size.height

        path.move(to: CGPoint(x: 0, y: length))
        path.addLine(to: .zero)
        path.addLine(to: CGPoint(x: length, y: 0))

        path.move(to: CGPoint(x: width - length, y: 0))
        path.addLine(to: CGPoint(x: width, y: 0))
        path.addLine(to: CGPoint(x: width, y: length))

        path.move(to: CGPoint(x: width, y: height - length))
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: width - length, y: height))

        path.move(to: CGPoint(x: length, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.addLine(to: CGPoint(x: 0, y: height - length))
      }
      .stroke(
        isTracking ? RehabPalette.mint : Color.white.opacity(0.48),
        style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
      )
      .shadow(
        color: isTracking ? RehabPalette.mint.opacity(0.55) : .clear,
        radius: 8
      )
      .animation(.easeOut(duration: 0.18), value: isTracking)
    }
    .accessibilityHidden(true)
  }
}

private struct PressableButtonStyle: ButtonStyle {
  var scale = 0.97

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? scale : 1)
      .opacity(configuration.isPressed ? 0.86 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
      .contentShape(Rectangle())
  }
}

enum RehabPalette {
  static let mint = Color(red: 0.55, green: 0.96, blue: 0.78)
  static let amber = Color(red: 1.0, green: 0.72, blue: 0.35)
  static let sky = Color(red: 0.49, green: 0.79, blue: 0.98)
}

struct TransferableVideo: Transferable {
  let url: URL

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(importedContentType: .movie) { received in
      let destination = URL.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(received.file.pathExtension)
      try FileManager.default.copyItem(at: received.file, to: destination)
      return TransferableVideo(url: destination)
    }
  }
}
