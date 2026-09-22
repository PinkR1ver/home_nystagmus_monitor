import SwiftUI
import UniformTypeIdentifiers
import AVKit
import Charts
import PhotosUI

private enum MotionStyle {
    static let red = Color(red: 1, green: 36/255, blue: 66/255)
    static let paper = Color(red: 247/255, green: 247/255, blue: 247/255)
    static let ink = Color(red: 34/255, green: 35/255, blue: 41/255)
    static let muted = Color(red: 119/255, green: 123/255, blue: 133/255)
    static let pale = Color(red: 1, green: 0.94, blue: 0.95)
}

private struct MotionRecord: Identifiable, Codable {
    var id: UUID
    var createdAt: Date
    var title: String
    var videoName: String
    var source: CaptureSource
    var imuSession: IMUSession?
    var eyeRegion: EyeRegion?
    var result: AnalysisResult?
    var message: String
}

@MainActor private final class MotionLibrary: ObservableObject {
    @Published var records: [MotionRecord] = []
    let directory: URL
    init() {
        directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("MotionLab", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let index = directory.appendingPathComponent("records.json")
            if FileManager.default.fileExists(atPath: index.path) {
                records = try JSONDecoder().decode([MotionRecord].self, from: Data(contentsOf: index))
            }
        } catch { loadError = "无法读取本机记录：\(error.localizedDescription)" }
    }
    @Published var loadError: String?
    func save() throws {
        try JSONEncoder().encode(records).write(to: directory.appendingPathComponent("records.json"), options: .atomic)
    }
    func importVideo(_ url: URL, title: String, source: CaptureSource) throws -> MotionRecord {
        let id = UUID()
        let name = "\(id.uuidString).\(url.pathExtension.isEmpty ? "mov" : url.pathExtension)"
        try FileManager.default.copyItem(at: url, to: directory.appendingPathComponent(name))
        let record = MotionRecord(id: id, createdAt: Date(), title: title, videoName: name, source: source, message: "视频已保存在本机")
        records.insert(record, at: 0)
        do { try save() } catch {
            records.removeAll { $0.id == id }
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            throw error
        }
        return record
    }
    func addIMU(_ session: IMUSession) throws -> MotionRecord {
        let record = MotionRecord(id: session.id, createdAt: session.startedAt, title: "前裤袋 IMU", videoName: session.fileName, source: .camera, imuSession: session, message: session.status == "completed" ? "采集已完成" : "采集已中断，原始数据已保留")
        records.insert(record, at: 0)
        try save()
        return record
    }
    func update(_ record: MotionRecord) throws {
        if let i = records.firstIndex(where: { $0.id == record.id }) { records[i] = record }
        try save()
    }
}

struct ContentView: View {
    @StateObject private var library = MotionLibrary()
    @StateObject private var imuCapture = IMUCapture()
    @State private var imuOptions = IMUOptions()
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = "首页"
    @State private var page = ""
    @State private var mode = "坐站 STS"
    @State private var camera = false
    @State private var importer = false
    @State private var photoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var eyeCapture = false
    @State private var busy = false
    @State private var error: String?
    @State private var selected: MotionRecord?
    @State private var saved = false
    @State private var roiRecord: MotionRecord?
    @State private var weight = UserDefaults.standard.string(forKey: "motion.weight") ?? ""
    @State private var height = UserDefaults.standard.string(forKey: "motion.height") ?? ""
    @State private var sex = UserDefaults.standard.string(forKey: "motion.sex") ?? "男性参数"

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let record = selected { report(record) }
                        else if page == "eye" { eyeEntry }
                        else if page == "cloud" { cloud }
                        else if page == "imu" { imu }
                        else if tab == "记录" { history }
                        else if tab == "我的" { profile }
                        else { home }
                    }
                    .padding(24)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                if page.isEmpty && selected == nil { tabBar }
            }
            if busy {
                Color.black.opacity(0.25).ignoresSafeArea()
                VStack(spacing: 18) {
                    ProgressView().tint(MotionStyle.red)
                    Text("正在分析眼动").font(.headline)
                    Text("视频已保存，请保持应用在前台。")
                        .font(.subheadline).foregroundStyle(MotionStyle.muted)
                }.padding(28).background(.white, in: RoundedRectangle(cornerRadius: 22))
            }
        }
        .foregroundStyle(MotionStyle.ink)
        .tint(MotionStyle.red)
        .preferredColorScheme(.light)
        .onChange(of: scenePhase) { _, phase in if phase != .active { imuCapture.stop(reason: "app_inactive") } }
        .onChange(of: weight) { saved = false }
        .onChange(of: height) { saved = false }
        .sheet(item: $roiRecord) { record in
            EyeRegionView(videoURL: library.directory.appendingPathComponent(record.videoName), initial: record.eyeRegion ?? EyeRegion()) { region in
                var updated = record
                updated.eyeRegion = region
                do {
                    try library.update(updated)
                    selected = updated
                    analyze(updated, source: updated.source)
                } catch { self.error = "选区保存失败：\(error.localizedDescription)" }
            }
        }
        .sheet(isPresented: $camera) {
            FixedLensCameraRecorder { url in
                camera = false
                if let url { accept(url, source: .camera) }
            }.ignoresSafeArea()
        }
        .photosPicker(isPresented: $photoPicker, selection: $photoItem, matching: .videos)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let movie = try await item.loadTransferable(type: MotionImportedMovie.self) else {
                        error = "无法读取所选视频。"; return
                    }
                    accept(movie.url, source: .importedVideo)
                    try? FileManager.default.removeItem(at: movie.url)
                } catch { self.error = "导入视频失败：\(error.localizedDescription)" }
                photoItem = nil
            }
        }
        .fileImporter(isPresented: $importer, allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie]) { result in
            switch result {
            case .success(let url): accept(url, source: .importedVideo)
            case .failure(let failure): error = failure.localizedDescription
            }
        }
        .alert("提示", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("知道了") { error = nil }
        } message: { Text(error ?? "") }
        .onAppear {
            error = library.loadError
            #if DEBUG
            if let route = ProcessInfo.processInfo.environment["MOTION_PREVIEW_PAGE"] {
                if ["eye", "cloud", "imu"].contains(route) { page = route }
                else if ["记录", "我的"].contains(route) { tab = route }
            }
            #endif
        }
    }

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 28, weight: .bold))
            Text(subtitle).font(.system(size: 15)).foregroundStyle(MotionStyle.muted)
        }
    }
    private func action(_ title: String, outlined: Bool = false, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title).font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .foregroundStyle(outlined ? MotionStyle.ink : .white)
                .background(outlined ? Color.white : MotionStyle.red, in: Capsule())
                .overlay(Capsule().stroke(outlined ? Color.gray.opacity(0.25) : Color.clear))
        }.buttonStyle(.plain)
    }
    private func back(_ title: String = "返回首页") -> some View {
        Button { imuCapture.stop(reason: "navigation"); page = ""; selected = nil } label: {
            Label(title, systemImage: "arrow.left").font(.system(size: 14))
        }.buttonStyle(.plain).frame(minHeight: 44)
    }
    private var home: some View {
        Group {
            heading("运动评估", "记录今天的状态")
            VStack(spacing: 4) {
                modeRow("静态站立", "站稳，观察身体摇摆")
                modeRow("步态", "走一段，观察步伐与节律")
                modeRow("坐站 STS", "坐下再站起，观察动作变化")
            }
            VStack(spacing: 12) {
                action("开始采集") { beginCapture(eye: false) }
                Button("从相册导入视频") { eyeCapture = false; photoPicker = true }
                    .foregroundStyle(MotionStyle.ink).frame(minHeight: 44)
            }
            Divider().overlay(MotionStyle.paper)
            Button { page = "eye" } label: {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("眼动检测").font(.system(size: 18, weight: .bold))
                        Text("录制眼部视频，查看眼动曲线与检测报告")
                            .font(.system(size: 12)).foregroundStyle(MotionStyle.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(MotionStyle.red)
                }.padding(20).background(MotionStyle.pale, in: RoundedRectangle(cornerRadius: 16))
            }.buttonStyle(.plain)
            Button { page = "imu" } label: {
                HStack { Image(systemName: "waveform.path"); Text("前裤袋 IMU 采集"); Spacer(); Image(systemName: "chevron.right") }
                    .font(.system(size: 15)).padding(.vertical, 12)
            }.buttonStyle(.plain)
            if let recent = library.records.first {
                Text("最近记录").font(.headline)
                recordRow(recent)
            }
            Text("视频与报告保存在本机").font(.system(size: 11)).foregroundStyle(MotionStyle.muted)
        }
    }
    private func modeRow(_ title: String, _ subtitle: String) -> some View {
        Button { mode = title } label: {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(mode == title ? MotionStyle.red : MotionStyle.ink)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(MotionStyle.muted)
                }
                Spacer()
                Image(systemName: mode == title ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(mode == title ? MotionStyle.red : Color.gray.opacity(0.3))
            }.padding(18).background(mode == title ? MotionStyle.pale : .white, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityAddTraits(mode == title ? .isSelected : [])
    }
    private var eyeEntry: some View {
        Group {
            back()
            heading("眼动检测", "记录眼睛的运动")
            VStack(alignment: .leading, spacing: 14) {
                Text("拍摄准备").font(.system(size: 18, weight: .bold))
                Text("固定手机和头部，让同一只眼睛清晰可见。保持照明稳定，避免反光和遮挡。")
                Text("建议录制 3–115 秒。保存完整视频后，先框选单眼区域，再在本机分析。导入视频最长 120 秒。")
                    .foregroundStyle(MotionStyle.muted)
            }.font(.system(size: 14)).lineSpacing(5).padding(20)
                .background(MotionStyle.paper, in: RoundedRectangle(cornerRadius: 16))
            action("录制眼部视频") { beginCapture(eye: true) }
            action("导入眼部视频", outlined: true) { eyeCapture = true; importer = true }
            Text("报告包括水平与垂直眼动曲线、信号质量及检测摘要。结果仅供观察记录，不能替代临床诊断。")
                .font(.system(size: 13)).foregroundStyle(MotionStyle.muted)
        }
    }
    private var history: some View {
        Group {
            heading("我的记录", "每一次练习，都值得认真记录。")
            action("云端同步与上传状态", outlined: true) { page = "cloud" }
            if library.records.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "doc.text").font(.system(size: 36)).foregroundStyle(MotionStyle.red)
                    Text("还没有采集记录").font(.headline)
                    Text("完成一次采集后，视频与报告会出现在这里。")
                        .font(.subheadline).foregroundStyle(MotionStyle.muted).multilineTextAlignment(.center)
                    Button("开始第一次采集") { tab = "首页" }.padding(8)
                }.frame(maxWidth: .infinity).padding(.vertical, 60)
            }
            ForEach(library.records) { recordRow($0) }
        }
    }
    private func recordRow(_ record: MotionRecord) -> some View {
        Button { selected = record; tab = "记录" } label: {
            HStack(spacing: 14) {
                Image(systemName: record.imuSession != nil ? "waveform.path" : record.title == "眼动检测" ? "eye" : "figure.walk")
                    .font(.title2).foregroundStyle(MotionStyle.red).frame(width: 48, height: 48)
                    .background(MotionStyle.pale, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 6) {
                    Text(record.title).font(.headline)
                    Text(record.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(MotionStyle.muted)
                    Text(record.result == nil ? record.message : "分析已完成 · 保存在本机").font(.caption).foregroundStyle(MotionStyle.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption)
            }.padding(18).background(MotionStyle.paper, in: RoundedRectangle(cornerRadius: 22))
        }.buttonStyle(.plain)
    }
    private var profile: some View {
        Group {
            heading("我的", "本机采集 · 可选云端同步")
            action("云端连接与同步", outlined: true) { page = "cloud" }
            Text("本次受试者").font(.system(size: 21, weight: .bold))
            field("体重（kg）", value: $weight)
            field("身高（cm）", value: $height)
            HStack(spacing: 12) {
                ForEach(["男性参数", "女性参数"], id: \.self) { item in
                    Button { sex = item; saved = false } label: {
                        Text(item).frame(maxWidth: .infinity).padding(14)
                            .foregroundStyle(sex == item ? MotionStyle.red : MotionStyle.muted)
                            .background(sex == item ? MotionStyle.pale : MotionStyle.paper, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
            action(saved ? "参数已保存" : "保存参数") {
                guard let w = Double(weight), let h = Double(height), (10...350).contains(w), (50...250).contains(h) else {
                    error = "请输入有效的体重（10–350 kg）和身高（50–250 cm）。"; return
                }
                UserDefaults.standard.set(weight, forKey: "motion.weight")
                UserDefaults.standard.set(height, forKey: "motion.height")
                UserDefaults.standard.set(sex, forKey: "motion.sex")
                saved = true
            }
            Divider()
            Text("关于运动实验室").font(.headline)
            Text("Apple 设计版 · 0.1.0\n沿用 Android 的运动、眼动与记录流程。\n已支持眼动与 IMU；身体姿态和云端同步正在移植。")
                .font(.system(size: 13)).foregroundStyle(MotionStyle.muted).lineSpacing(6)
        }
    }
    private func field(_ title: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(MotionStyle.muted)
            TextField(title, text: value).keyboardType(.decimalPad).padding(16)
                .background(MotionStyle.paper, in: RoundedRectangle(cornerRadius: 14))
        }
    }
    private var cloud: some View {
        Group {
            back("返回")
            heading("云端同步", "安全保存视频、眼动与运动报告、IMU 原始数据。")
            VStack(alignment: .leading, spacing: 12) {
                Text("服务器地址").font(.subheadline).foregroundStyle(MotionStyle.muted)
                Text("https://39.107.192.82").font(.system(.body, design: .monospaced)).textSelection(.enabled)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                .background(MotionStyle.paper, in: RoundedRectangle(cornerRadius: 16))
            Label("尚未连接", systemImage: "cloud").foregroundStyle(MotionStyle.muted)
            Text("Apple 版的账户连接与上传队列正在接入。本版只在本机保存，暂不上传采集数据。")
                .font(.subheadline).foregroundStyle(MotionStyle.muted)
            Text("连接凭据、同步进度与逐条上传状态将与 Android 版保持一致。")
                .font(.caption).foregroundStyle(MotionStyle.muted)
        }
    }
    private var imu: some View {
        Group {
            back()
            heading("前裤袋 IMU 采集", "记录身体运动的原始信号")
            Text("将手机放入前裤袋，保持方向固定。采集期间请保持应用在前台；离开应用会停止并保存已有数据。")
                .font(.subheadline).foregroundStyle(MotionStyle.muted)
            VStack(spacing: 16) {
                TextField("受试者编号（可选）", text: $imuOptions.participant).textFieldStyle(.roundedBorder)
                Picker("放置位置", selection: $imuOptions.pocket) {
                    Text("右前裤袋").tag("right_front"); Text("左前裤袋").tag("left_front")
                }.pickerStyle(.segmented)
                Picker("手机顶部", selection: $imuOptions.phoneTop) { Text("向上").tag("up"); Text("向下").tag("down") }.pickerStyle(.segmented)
                Picker("屏幕方向", selection: $imuOptions.screenFacing) { Text("朝向身体").tag("body"); Text("朝向外侧").tag("outward") }.pickerStyle(.segmented)
                Picker("自动停止", selection: $imuOptions.limitMinutes) {
                    ForEach([1,5,10,30], id: \.self) { Text("\($0) 分钟").tag($0) }
                }
            }.disabled(imuCapture.active)
            HStack {
                metric("已采集", "\(Int(imuCapture.duration)) 秒")
                metric("原始样本", "\(imuCapture.sampleCount)")
            }
            if let message = imuCapture.error { Text(message).foregroundStyle(.red).font(.subheadline) }
            if imuCapture.active {
                action("添加事件标记", outlined: true) { imuCapture.marker() }
                action("停止并保存") { imuCapture.stop() }
            } else {
                action("开始 IMU 采集") {
                    imuCapture.start(directory: library.directory, options: imuOptions) { session in
                        do {
                            selected = try library.addIMU(session)
                            page = ""; tab = "记录"
                        } catch { self.error = "保存记录失败：\(error.localizedDescription)" }
                    }
                }
            }
            Text("目标 100 Hz；实际频率取决于设备。加速度包含重力，单位 m/s²；角速度单位 rad/s。原始数据保留设备坐标系。")
                .font(.caption).foregroundStyle(MotionStyle.muted)
        }
    }
    private func report(_ record: MotionRecord) -> some View {
        Group {
            back("返回记录")
            heading(record.title + "报告", record.createdAt.formatted(date: .abbreviated, time: .shortened))
            if let imu = record.imuSession {
                HStack { metric("时长", "\(Int(imu.durationS)) 秒"); metric("状态", imu.status == "completed" ? "已完成" : "已中断") }
                ForEach(["accelerometer", "gyroscope"], id: \.self) { sensor in
                    if let stats = imu.summaries[sensor] {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(sensor == "accelerometer" ? "加速度计" : "陀螺仪").font(.headline)
                            Text("\(stats.count) 个样本 · 最大间隔 \(Int(stats.maxGapMs)) ms")
                            Text("超过 100 ms 的间隔：\(stats.gapsOver100Ms)；时间异常：\(stats.nonIncreasing)").font(.caption)
                        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(MotionStyle.paper, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                ShareLink("导出采集信息", item: library.directory.appendingPathComponent(imu.metadataName))
                ShareLink("导出事件标记", item: library.directory.appendingPathComponent(imu.markersName))
            } else {
            VideoPlayer(player: AVPlayer(url: library.directory.appendingPathComponent(record.videoName)))
                .frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 16))
            if let result = record.result {
                Text(result.finding == .detected ? "观察到眼动信号" : result.finding == .notDetected ? "未见明确眼动信号" : "建议重新采集")
                    .font(.title3.bold()).foregroundStyle(MotionStyle.red)
                Text(result.summary).font(.subheadline).foregroundStyle(MotionStyle.muted)
                HStack {
                    metric("视频时长", "\(Int(result.durationSeconds)) 秒")
                    metric("信号质量", "\(Int(result.qualityScore * 100))%")
                }
                signalChart("水平眼动", samples: result.samples, horizontal: true)
                signalChart("垂直眼动", samples: result.samples, horizontal: false)
                Text("本机分析 · 仅供观察记录，不能替代临床诊断。")
                    .font(.caption).foregroundStyle(MotionStyle.muted)
            } else {
                Text(record.message).foregroundStyle(MotionStyle.muted)
                if record.title == "眼动检测" {
                    action("选择单眼区域并分析") { roiRecord = record }
                } else {
                    Text("身体姿态模型尚未移植。原始视频已保存，当前不生成运动指标。")
                        .font(.subheadline).foregroundStyle(MotionStyle.muted)
                }
            }
            }
            ShareLink(item: library.directory.appendingPathComponent(record.videoName)) {
                Label(record.imuSession == nil ? "导出原始视频" : "导出原始 IMU CSV", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(16)
            }
        }
    }
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption).foregroundStyle(MotionStyle.muted)
            Text(value).font(.title3.bold())
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(MotionStyle.paper, in: RoundedRectangle(cornerRadius: 16))
    }
    private func signalChart(_ title: String, samples: [GazeSample], horizontal: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            Chart(samples.filter { $0.time.isFinite && (horizontal ? $0.horizontal : $0.vertical).isFinite }) { sample in
                LineMark(x: .value("时间（秒）", sample.time), y: .value("角度", horizontal ? sample.horizontal : sample.vertical))
                    .foregroundStyle(MotionStyle.red)
            }.frame(height: 150)
        }.padding(18).background(MotionStyle.paper, in: RoundedRectangle(cornerRadius: 16))
    }
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach([("首页", "house"), ("记录", "doc.text"), ("我的", "person")], id: \.0) { item in
                Button { tab = item.0 } label: {
                    VStack(spacing: 7) {
                        Image(systemName: item.1 + (tab == item.0 ? ".fill" : "")).font(.system(size: 20))
                        Text(item.0).font(.system(size: 11, weight: tab == item.0 ? .semibold : .regular))
                    }.foregroundStyle(tab == item.0 ? MotionStyle.red : MotionStyle.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                }.buttonStyle(.plain).accessibilityAddTraits(tab == item.0 ? .isSelected : [])
            }
        }.background(.white).overlay(alignment: .top) { Divider() }
    }
    private func beginCapture(eye: Bool) {
        eyeCapture = eye
        #if targetEnvironment(simulator)
        error = "模拟器没有相机。请导入视频，或在 iPhone / iPad 上录制。"
        #else
        camera = true
        #endif
    }
    private func accept(_ url: URL, source: CaptureSource) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let record = try library.importVideo(url, title: eyeCapture ? "眼动检测" : mode, source: source)
            selected = record
            page = ""
            tab = "记录"
            // Save first; analysis is explicitly initiated from the saved record.
        } catch { self.error = "保存视频失败：\(error.localizedDescription)" }
    }
    private func analyze(_ record: MotionRecord, source: CaptureSource) {
        busy = true
        let url = library.directory.appendingPathComponent(record.videoName)
        Task {
            var updated = record
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let duration = try await AVURLAsset(url: url).load(.duration).seconds
                    guard duration.isFinite, duration >= 3, duration <= 120 else { throw MotionVideoError.duration }
                    return try await PrototypeNystagmusAnalysisEngine(fixedRegion: record.eyeRegion).analyze(videoURL: url, source: source)
                }.value
                updated.result = result
                updated.message = "分析已完成"
            } catch { updated.message = "未能完成分析：\(error.localizedDescription)" }
            do { try library.update(updated) } catch { self.error = "报告保存失败：\(error.localizedDescription)" }
            selected = updated
            busy = false
        }
    }
}

private enum MotionVideoError: LocalizedError {
    case duration
    var errorDescription: String? { "请选择 3–120 秒的视频。原始文件已保留，可导出后裁剪。" }
}

private struct MotionImportedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: url)
            return Self(url: url)
        }
    }
}
