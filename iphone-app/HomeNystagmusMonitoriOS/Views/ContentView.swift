import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var result: AnalysisResult?
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var showingCamera = false
    @State private var showingUSBCameraSetup = false
    @State private var showingUSBCameraCapture = false
    @State private var usbCaptureSettings: USBVideoCaptureSettings?
    @State private var showingImporter = false
    @State private var showingUSBCameraParameters = false
    @State private var showingPrincipleFigure = false

    private let engine: NystagmusAnalysisEngine = PrototypeNystagmusAnalysisEngine()

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 760

            ZStack {
                AppBackground()

                VStack(spacing: isCompact ? 12 : 16) {
                    if let result {
                        DashboardView(result: result, isCompact: isCompact) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                self.result = nil
                                errorMessage = nil
                            }
                        }
                    } else {
                        HeaderView(isCompact: isCompact)
                        CaptureStartView(
                            isAnalyzing: isAnalyzing,
                            errorMessage: errorMessage,
                            isCompact: isCompact,
                            onStartCamera: {
                                showingCamera = true
                            },
                            onStartUSBCamera: {
                                showingUSBCameraSetup = true
                            },
                            onImportVideo: { showingImporter = true },
                            onUSBCamera: { showingUSBCameraParameters = true },
                            onShowPrinciple: { showingPrincipleFigure = true }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 18)
                .padding(.top, isCompact ? 8 : 12)
                .padding(.bottom, isCompact ? 8 : 12)

                if isAnalyzing {
                    AnalyzingOverlay()
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            FixedLensCameraRecorder { url in
                showingCamera = false
                guard let url else { return }
                analyze(url: url, source: .camera)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingUSBCameraSetup) {
            NavigationStack {
                USBCameraCaptureSetupView { settings in
                    usbCaptureSettings = settings
                    showingUSBCameraSetup = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showingUSBCameraCapture = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingUSBCameraCapture) {
            if let usbCaptureSettings {
                ExternalUSBCameraRecorder(settings: usbCaptureSettings) { url in
                    showingUSBCameraCapture = false
                    guard let url else { return }
                    analyze(url: url, source: .camera)
                }
                .ignoresSafeArea()
            } else {
                ContentUnavailableView("No USB capture settings", systemImage: "video.slash")
            }
        }
        .sheet(isPresented: $showingUSBCameraParameters) {
            NavigationStack {
                USBCameraParametersView()
            }
        }
        .sheet(isPresented: $showingPrincipleFigure) {
            NavigationStack {
                PrincipleFigureView()
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { response in
            switch response {
            case .success(let urls):
                guard let url = urls.first else { return }
                analyze(url: url, source: .importedVideo)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func analyze(url: URL, source: CaptureSource) {
        Task {
            await MainActor.run {
                errorMessage = nil
                isAnalyzing = true
            }

            let accessGranted = url.startAccessingSecurityScopedResource()
            defer {
                if accessGranted {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let analysis = try await engine.analyze(videoURL: url, source: source)
                await MainActor.run {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                        result = analysis
                        isAnalyzing = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isAnalyzing = false
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
