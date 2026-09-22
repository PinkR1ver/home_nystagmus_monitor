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
    var cloudRecordId: String?
    var cloudRecord: CloudJSON?
    var cloudOnly: Bool?
    var cloudArchived: Bool?
    var cloudOwner: String?
    var bodyReport: BodyAnalysisReport?
    var subject: BodySubject?
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
    func mergeCloud(_ remote:[String:CloudJSON],scope:String) throws {
        var merged=records
        for i in merged.indices where merged[i].cloudOwner == scope && merged[i].cloudRecordId != nil {
            if remote[merged[i].cloudRecordId!] == nil {merged[i].cloudArchived=true}
        }
        for(id,server) in remote.sorted(by:{($0.value["revision"].number ?? 0)<($1.value["revision"].number ?? 0)}) {
            let localId=server["metadata"]["context"]["localRecordId"].string.flatMap(UUID.init(uuidString:))
            let position=merged.firstIndex {r in r.cloudOwner == scope && (r.cloudRecordId == id || (localId != nil && r.id == localId))}
            let type=server["task_type"].string ?? ""
            let title=["eye":"眼动检测","standing":"静态站立","gait":"步态","sts":"坐站 STS","imu":"前裤袋 IMU"][type] ?? "云端记录"
            var record=position.map{merged[$0]} ?? MotionRecord(id:UUID(),createdAt:ISO8601DateFormatter().date(from:server["metadata"]["startedAt"].string ?? "") ?? Date(),title:title,videoName:"",source:.importedVideo,cloudOnly:true,cloudOwner:scope,message:"云端记录，原始文件尚未下载")
            record.cloudRecordId=id;record.cloudRecord=server;record.cloudArchived=false
            let reports=server["reports"].array
            if let report=reports.last(where:{$0["origin"].string == "server"}) ?? reports.last {
                let payload=try report["payload"].data()
                if report["origin"].string == "server" {record.bodyReport=nil;record.result=nil}
                if let body=try? JSONDecoder().decode(BodyAnalysisReport.self,from:payload) {record.bodyReport=body;record.result=nil;try payload.write(to:directory.appendingPathComponent(record.id.uuidString+"-body-report.json"),options:.atomic)}
                else if let eye=try? JSONDecoder().decode(AnalysisResult.self,from:payload) {record.result=eye;record.bodyReport=nil}
            }
            if let position {merged[position]=record}else{merged.append(record)}
        }
        let previous=records;records=merged.sorted{$0.createdAt>$1.createdAt}
        do{try save()}catch{records=previous;throw error}
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
    @StateObject private var cloudSync = MotionCloud()
    private var visibleRecords:[MotionRecord] {
        library.records.filter {record in
            if record.cloudOnly == true {return record.cloudOwner == cloudSync.scope && record.cloudArchived != true}
            return true
        }
    }
    @State private var cloudEndpoint = "https://39.107.192.82"
    @State private var cloudSecret = ""
    @State private var credentialImporter = false
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
    @State private var analysisTitle = "正在分析"
    @State private var smokeStarted = false
    @State private var error: String?
    @State private var selected: MotionRecord?
    @State private var saved = false
    @State private var roiRecord: MotionRecord?
    @State private var reportArchive: URL?
    @State private var exporting = false
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
                    Text(analysisTitle).font(.headline)
                    Text("视频已保存，请保持应用在前台。")
                        .font(.subheadline).foregroundStyle(MotionStyle.muted)
                }.padding(28).background(.white, in: RoundedRectangle(cornerRadius: 22))
            }
        }
        .foregroundStyle(MotionStyle.ink)
        .tint(MotionStyle.red)
        .preferredColorScheme(.light)
        .onChange(of: scenePhase) { _, phase in if phase != .active { imuCapture.stop(reason: "app_inactive"); cloudSync.pause() } }
        .onChange(of: cloudSync.state.records) { _, records in
            if let scope=cloudSync.scope {
                do{try library.mergeCloud(records,scope:scope)}catch{self.error="云端记录合并失败：\(error.localizedDescription)"}
            }
        }
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
            FixedLensCameraRecorder(bodyGuide: eyeCapture ? nil : mode) { url in
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
        .fileImporter(isPresented: $credentialImporter, allowedContentTypes: [.json, .plainText]) { result in
            do {
                let url=try result.get();let access=url.startAccessingSecurityScopedResource()
                defer {if access {url.stopAccessingSecurityScopedResource()}}
                let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
                guard size <= 16384 else {throw MotionCloudFailure(status:0,message:"凭据文件过大")}
                cloudSecret=try String(contentsOf:url,encoding:.utf8)
            }catch{self.error=error.localizedDescription}
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
        .onAppear(perform: handleAppearance)
    }

    private func handleAppearance() {
            error = library.loadError
            if let scope=cloudSync.scope {do{try library.mergeCloud(cloudSync.state.records,scope:scope)}catch{self.error=error.localizedDescription}}
            #if DEBUG
            if ProcessInfo.processInfo.environment["MOTION_SMOKE_CLOUD"] == "1", !smokeStarted {
                smokeStarted = true
                Task {await CloudRuntimeSmoke.run()}
            }
            if ProcessInfo.processInfo.environment["MOTION_SMOKE_BODY"] == "1", !smokeStarted {
                smokeStarted = true
                let fixture = library.directory.appendingPathComponent("runtime-input.mp4")
                accept(fixture, source: .importedVideo)
                if let record = selected { analyzeBody(record) }
            }
            if ProcessInfo.processInfo.environment["MOTION_SMOKE_EYE"] == "1", !smokeStarted {
                smokeStarted = true
                let fixture = library.directory.appendingPathComponent("eye-runtime-input.mp4")
                var record: MotionRecord?
                do {
                    eyeCapture = true
                    record = try library.importVideo(fixture, title: "眼动检测", source: .importedVideo)
                    if var record {
                        record.eyeRegion = EyeRegion(x: 0.05, y: 0.35, width: 0.5, height: 0.45)
                        try library.update(record)
                        selected = record
                        do { record.message = "眼动验收：开始 ONNX 分析"; try library.update(record) } catch { self.error = error.localizedDescription }
                        analyze(record, source: .importedVideo)
                    }
                } catch { self.error = "眼动运行验收准备失败：\(error.localizedDescription)" }
            }
            if let route = ProcessInfo.processInfo.environment["MOTION_PREVIEW_PAGE"] {
                if ["eye", "cloud", "imu"].contains(route) { page = route }
                else if ["记录", "我的"].contains(route) { tab = route }
            }
            #endif
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
            if let recent = visibleRecords.first {
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
            if visibleRecords.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "doc.text").font(.system(size: 36)).foregroundStyle(MotionStyle.red)
                    Text("还没有采集记录").font(.headline)
                    Text("完成一次采集后，视频与报告会出现在这里。")
                        .font(.subheadline).foregroundStyle(MotionStyle.muted).multilineTextAlignment(.center)
                    Button("开始第一次采集") { tab = "首页" }.padding(8)
                }.frame(maxWidth: .infinity).padding(.vertical, 60)
            }
            ForEach(visibleRecords) { recordRow($0) }
        }
    }
    private func recordRow(_ record: MotionRecord) -> some View {
        Button { reportArchive=nil; selected = record; tab = "记录" } label: {
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
            Text("Apple 设计版 · 0.1.0\n沿用 Android 的运动、眼动与记录流程。\n支持运动、眼动、IMU 与可选云端同步。")
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
            if let credential=cloudSync.credential {
                Label("已连接",systemImage:"checkmark.shield.fill").foregroundStyle(MotionStyle.red)
                Text(credential.endpoint).font(.subheadline)
                Text("账户："+credential.accountId).font(.caption).textSelection(.enabled)
                if cloudSync.busy {
                    ProgressView()
                    action("暂停同步",outlined:true) {cloudSync.pause()}
                }else{
                    action("上传本机记录并同步") {prepareCloudUploads()}
                    action("仅拉取云端及重试队列",outlined:true) {cloudSync.sync()}
                    Button("断开连接") {cloudSync.disconnect()}
                }
                Text("首次同步会将未绑定的本机记录绑定到此账户。上传原始视频与报告；修改后的报告以新版本记录上传。")
                    .font(.caption).foregroundStyle(MotionStyle.muted)
                ForEach(cloudSync.state.uploads) { upload in
                    VStack(alignment:.leading,spacing:6) {
                        Text(upload.localId.uuidString.prefix(8)).font(.subheadline.bold())
                        Text(upload.message).font(.caption).foregroundStyle(MotionStyle.muted)
                    }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(MotionStyle.paper,in:RoundedRectangle(cornerRadius:16))
                }
                Text("云端记录").font(.headline)
                ForEach(cloudSync.state.records.keys.sorted(),id:\.self) { id in
                    let record=cloudSync.state.records[id]
                    VStack(alignment:.leading,spacing:8) {
                        Text(record?["task_type"].string ?? "记录").font(.headline)
                        Text(record?["metadata"]["startedAt"].string ?? "").font(.caption)
                        Text(record?["status"].string ?? "").font(.caption).foregroundStyle(MotionStyle.muted)
                        if let reports=record?["reports"].array,!reports.isEmpty {
                            ForEach(Array(reports.enumerated()),id:\.offset) { _,report in
                                Text((report["origin"].string ?? "")+" · "+(report["outcome"].string ?? "")).font(.caption)
                                Text(report["payload"]["summary"].string ?? report["payload"]["message"].string ?? report["version"].string ?? "报告已保存").font(.subheadline)
                            }
                        }
                    }.padding(18).frame(maxWidth:.infinity,alignment:.leading).background(MotionStyle.paper,in:RoundedRectangle(cornerRadius:16))
                }
            }else{
                TextField("HTTPS 服务器地址",text:$cloudEndpoint).textInputAutocapitalization(.never).autocorrectionDisabled().padding(16).background(MotionStyle.paper,in:RoundedRectangle(cornerRadius:16))
                SecureField("访问令牌或连接凭据 JSON",text:$cloudSecret).textInputAutocapitalization(.never).autocorrectionDisabled().padding(16).background(MotionStyle.paper,in:RoundedRectangle(cornerRadius:16))
                action("导入连接凭据",outlined:true) {credentialImporter=true}
                action("验证并连接") {Task {await cloudSync.connect(endpoint:cloudEndpoint,secret:cloudSecret);if cloudSync.credential != nil {cloudSecret=""}}}.disabled(cloudSync.busy)
            }
            if !cloudSync.message.isEmpty {Text(cloudSync.message).font(.subheadline).foregroundStyle(MotionStyle.muted)}
        }
    }
    private func prepareCloudUploads() {
        guard let scope=cloudSync.scope,!busy,!imuCapture.active else {error="请先完成当前采集或分析";return}
        do {
            for original in library.records where original.cloudOnly != true && (original.cloudOwner == nil || original.cloudOwner == scope) {
                var record=original
                if record.cloudOwner == nil {record.cloudOwner=scope;try library.update(record)}
                let kind=record.imuSession != nil ? "imu" : record.title == "眼动检测" ? "eye" : record.title == "步态" ? "gait" : record.title == "静态站立" ? "standing" : "sts"
                let duration=record.imuSession?.durationS ?? record.bodyReport?.durationS ?? record.result?.durationSeconds ?? 0
                let metadata=CloudJSON.object(["schemaVersion":.number(1),"taskType":.string(kind),"startedAt":.string(ISO8601DateFormatter().string(from:record.createdAt)),"durationSec":.number(duration),"device":.object(["platform":.string("ios")]),"context":.object(["localRecordId":.string(record.id.uuidString),"subject":try record.subject.map {try CloudJSON.wrap($0)} ?? .null]),"subjectId":.null])
                var artifacts:[String:URL]=[kind == "imu" ? "imu.csv" : "video.mp4":library.directory.appendingPathComponent(record.videoName)]
                let landmarks=library.directory.appendingPathComponent(record.id.uuidString+"-landmarks.json")
                if FileManager.default.fileExists(atPath:landmarks.path) {artifacts["landmarks.json"]=landmarks}
                var report:CloudJSON?
                if let body=record.bodyReport {report = .object(["version":.string(body.version),"outcome":.string("analyzed"),"payload":try .wrap(body)])}
                else if let eye=record.result {report = .object(["version":.string("apple-eye-v1"),"outcome":.string(eye.finding == .inconclusive ? "unable_to_analyze":"analyzed"),"payload":try .wrap(eye)])}
                else if record.message.hasPrefix("无法分析") || record.message.hasPrefix("未能完成分析") {report = .object(["version":.string("apple-unavailable-v1"),"outcome":.string("unable_to_analyze"),"payload":.object(["message":.string(record.message)])])}
                let contextURL=library.directory.appendingPathComponent(record.id.uuidString+"-upload-context.json")
                let context:CloudJSON = .object(["subject":try record.subject.map{try .wrap($0)} ?? .null,"eyeRegion":try record.eyeRegion.map{try .wrap($0)} ?? .null,"imu":try record.imuSession.map{try .wrap($0)} ?? .null])
                try context.data().write(to:contextURL,options:.atomic);artifacts["test_context.json"]=contextURL
                try cloudSync.enqueue(localId:record.id,metadata:metadata,report:report,artifacts:artifacts)
            }
            cloudSync.sync()
        }catch{self.error="准备同步失败：\(error.localizedDescription)"}
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
                action(imuCapture.finishing ? "正在保存…":"开始 IMU 采集") {
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
            if let remote=record.cloudRecord {
                Text(record.cloudArchived == true ? "云端已归档 · 本机数据保留" : "云端记录已同步").font(.caption).foregroundStyle(MotionStyle.muted)
                let reports=remote["reports"].array
                if let report=reports.last(where:{$0["origin"].string == "server"}) ?? reports.last {
                    Text("\(report["origin"].string == "server" ? "服务器分析":"客户端分析") · \(report["version"].string ?? "")").font(.caption)
                    Text(report["payload"]["summary"].string ?? report["payload"]["message"].string ?? "").font(.subheadline)
                }
            }
            if record.videoName.isEmpty,let serverId=record.cloudRecordId,record.cloudArchived != true {
                action("下载原始文件") {
                    Task {
                        let name=record.cloudRecord?["task_type"].string == "imu" ? "imu.csv":"video.mp4"
                        let localName=record.id.uuidString+"-download-"+name
                        do {
                            guard record.cloudOwner == cloudSync.scope else {throw MotionCloudFailure(status:0,message:"请切换到此记录所属账户")}
                            try await cloudSync.download(recordId:serverId,name:name,to:library.directory.appendingPathComponent(localName))
                            var updated=record;updated.videoName=localName;try library.update(updated);selected=updated
                        }catch{self.error=error.localizedDescription}
                    }
                }.disabled(cloudSync.busy)
            }
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
            if !record.videoName.isEmpty && record.cloudRecord?["task_type"].string != "imu" {
            VideoPlayer(player: AVPlayer(url: library.directory.appendingPathComponent(record.videoName)))
                .frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 16))
            }
            if let body = record.bodyReport {
                HStack { metric("有效覆盖", "\(Int(body.validCoverage*100))%"); metric(body.mode == "sts" ? "完整起立":"视频时长", body.mode == "sts" ? "\(body.events.filter { $0.direction == "rise" && $0.status == "accepted" }.count)":"\(Int(body.durationS)) 秒") }
                Text("身体质心与惯量").font(.headline)
                Chart(Array(body.signals.enumerated()), id: \.offset) { index, sample in
                    if let value=sample.inertia {
                        LineMark(x:.value("时间（秒）",sample.timeS),y:.value("惯量 / 质量（m²）",value),series:.value("连续段",body.signals[..<index].lastIndex(where:{$0.inertia == nil}) ?? -1)).foregroundStyle(MotionStyle.red)
                    }
                }.frame(height:180)
                ForEach(Array(body.events.enumerated()), id: \.offset) { _, event in
                    VStack(alignment:.leading,spacing:6) {
                        Text("\(event.direction == "rise" ? "起立" : event.direction == "sit" ? "坐下" : "未完成动作") · \(event.status == "accepted" ? "完整" : "需复核")").font(.headline)
                        Text(String(format:"%.2f–%.2f 秒",event.startS,event.endS)).font(.subheadline)
                        if !event.reason.isEmpty { Text(event.reason).font(.caption).foregroundStyle(MotionStyle.muted) }
                    }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(MotionStyle.paper,in:RoundedRectangle(cornerRadius:16))
                }
                BodyMotionReportView(report:body)
                ForEach(body.stats.keys.sorted(),id:\.self) { key in
                    if let stats=body.stats[key], let mean=stats.mean {
                        HStack { Text(key).font(.caption);Spacer();Text(String(format:"%.3f",mean)).monospacedDigit() }
                    }
                }
                ForEach(body.warnings,id:\.self) { Text($0).font(.caption).foregroundStyle(MotionStyle.muted) }
                ShareLink("导出身体分析 JSON",item:library.directory.appendingPathComponent(record.id.uuidString+"-body-report.json"))
                if FileManager.default.fileExists(atPath:library.directory.appendingPathComponent(record.id.uuidString+"-landmarks.json").path) {
                ShareLink("导出原始关键点 JSON",item:library.directory.appendingPathComponent(record.id.uuidString+"-landmarks.json"))
                }
            } else if let result = record.result {
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
                if record.title == "眼动检测" && !record.videoName.isEmpty {
                    action("选择单眼区域并分析") { roiRecord = record }
                } else if record.cloudRecord?["task_type"].string != "imu" && !record.videoName.isEmpty {
                    action("分析身体运动") { analyzeBody(record) }
                }
            }
            }
            action(exporting ? "正在打包…":"导出报告与原始数据 ZIP",outlined:true) {exportRecord(record)}.disabled(exporting)
            if let reportArchive {ShareLink("分享导出文件",item:reportArchive)}
            if !record.videoName.isEmpty {
            ShareLink(item: library.directory.appendingPathComponent(record.videoName)) {
                Label(record.imuSession == nil && record.cloudRecord?["task_type"].string != "imu" ? "导出原始视频" : "导出原始 IMU CSV", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(16)
            }
            }
        }
    }
    private func exportRecord(_ record:MotionRecord) {
        exporting=true;reportArchive=nil
        let directory=library.directory
        Task {
            do {
                let output=try await Task.detached(priority:.userInitiated) {
                    let staging=FileManager.default.temporaryDirectory.appendingPathComponent("motion-export-"+UUID().uuidString,isDirectory:true)
                    try FileManager.default.createDirectory(at:staging,withIntermediateDirectories:true)
                    defer{try? FileManager.default.removeItem(at:staging)}
                    var files:[String:URL]=[:]
                    func write(_ name:String,_ data:Data)throws {let url=staging.appendingPathComponent(name);try data.write(to:url,options:.atomic);files[name]=url}
                    let context=CloudJSON.object(["recordId":.string(record.id.uuidString),"createdAt":.string(ISO8601DateFormatter().string(from:record.createdAt)),"source":.string(record.source.rawValue),"subject":try record.subject.map{try .wrap($0)} ?? .null,"eyeRegion":try record.eyeRegion.map{try .wrap($0)} ?? .null,"message":.string(record.message)])
                    try write("test_context.json",context.data())
                    if let body=record.bodyReport {
                        try write("report.json",JSONEncoder().encode(body))
                        if let motion=body.motion {
                            var rows="key,label,unit,group,value,reason,n\n"
                            for metric in motion.metrics {
                                rows += [metric.key,metric.label,metric.unit,metric.group,metric.value.map{String($0)} ?? "",metric.reason ?? "",String(metric.n)].map(MotionArchive.csvCell).joined(separator:",")+"\n"
                            }
                            try write("metrics.csv",Data(rows.utf8))
                            var signals="time_s,"+motion.series.map{MotionArchive.csvCell($0.key)}.joined(separator:",")+"\n"
                            for i in body.signals.indices {signals += String(body.signals[i].timeS)+","+motion.series.map{i<$0.values.count ? $0.values[i].map{String($0)} ?? "":""}.joined(separator:",")+"\n"}
                            try write("signals.csv",Data(signals.utf8))
                        }
                        let landmarks=directory.appendingPathComponent(record.id.uuidString+"-landmarks.json")
                        if FileManager.default.fileExists(atPath:landmarks.path){files["landmarks.json"]=landmarks}
                    }
                    if let eye=record.result {
                        try write("eye_report.json",JSONEncoder().encode(eye))
                        var raw="time_ms,yaw_deg,pitch_deg\n"
                        for sample in eye.rawSamples ?? [] {raw += "\(sample.timeMs),\(sample.yawDeg.map{String($0)} ?? ""),\(sample.pitchDeg.map{String($0)} ?? "")\n"}
                        try write("eye_signals.csv",Data(raw.utf8))
                    }
                    if let imu=record.imuSession {
                        files["imu.csv"]=directory.appendingPathComponent(imu.fileName)
                        files["markers.csv"]=directory.appendingPathComponent(imu.markersName)
                        try write("imu_meta.json",JSONEncoder().encode(imu))
                    }
                    if let remote=record.cloudRecord {try write("cloud_record.json",remote.data())}
                    let output=directory.appendingPathComponent(record.id.uuidString+"-"+UUID().uuidString.prefix(8)+"-report.zip")
                    try MotionArchive.write(files:files,to:output)
                    return output
                }.value
                reportArchive=output
            }catch{self.error="导出失败：\(error.localizedDescription)"}
            exporting=false
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
            var record = try library.importVideo(url, title: eyeCapture ? "眼动检测" : mode, source: source)
            record.subject = BodySubject(massKg:Double(weight) ?? 67,heightCm:Double(height) ?? 173,profile:sex == "女性参数" ? "F" : "M")
            try library.update(record)
            selected = record
            page = ""
            tab = "记录"
            // Save first; analysis is explicitly initiated from the saved record.
        } catch { self.error = "保存视频失败：\(error.localizedDescription)" }
    }
    private func analyzeBody(_ record: MotionRecord) {
        busy=true;analysisTitle="正在分析身体运动"
        let url=library.directory.appendingPathComponent(record.videoName)
        let directory=library.directory
        let mode=record.title == "步态" ? "gait" : record.title == "静态站立" ? "standing" : "sts"
        Task {
            var updated=record
            do {
                let output=try await Task.detached(priority:.userInitiated) {
                    try await BodyVideoAnalysis().analyze(video:url,subject:record.subject ?? BodySubject(),mode:mode)
                }.value
                try JSONEncoder().encode(output.frames).write(to:directory.appendingPathComponent(record.id.uuidString+"-landmarks.json"),options:.atomic)
                try JSONEncoder().encode(output.report).write(to:directory.appendingPathComponent(record.id.uuidString+"-body-report.json"),options:.atomic)
                updated.bodyReport=output.report;updated.message="身体分析已完成"
            } catch { updated.message="无法分析：\(error.localizedDescription)" }
            do { try library.update(updated) } catch { self.error="记录保存失败：\(error.localizedDescription)" }
            selected=updated;busy=false
        }
    }
    private func analyze(_ record: MotionRecord, source: CaptureSource) {
        analysisTitle = "正在分析眼动"
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
