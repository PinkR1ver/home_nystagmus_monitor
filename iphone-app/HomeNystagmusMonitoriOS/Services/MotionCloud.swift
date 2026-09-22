import Foundation
import Security
import CryptoKit
import SwiftUI

enum CloudJSON: Codable, Equatable {
    case object([String:CloudJSON]), array([CloudJSON]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c=try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let x=try? c.decode(Bool.self) { self = .bool(x) }
        else if let x=try? c.decode(String.self) { self = .string(x) }
        else if let x=try? c.decode(Double.self) { self = .number(x) }
        else if let x=try? c.decode([String:CloudJSON].self) { self = .object(x) }
        else { self = .array(try c.decode([CloudJSON].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c=encoder.singleValueContainer()
        switch self { case .object(let x):try c.encode(x);case .array(let x):try c.encode(x);case .string(let x):try c.encode(x);case .number(let x):try c.encode(x);case .bool(let x):try c.encode(x);case .null:try c.encodeNil() }
    }
    subscript(_ key: String) -> CloudJSON { if case .object(let x)=self { return x[key] ?? .null };return .null }
    var string: String? { if case .string(let x)=self {return x};return nil }
    var number: Double? { if case .number(let x)=self {return x};return nil }
    var array: [CloudJSON] { if case .array(let x)=self {return x};return [] }
    var bool: Bool { if case .bool(let x)=self {return x};return false }
    static func wrap<T:Encodable>(_ value:T) throws -> Self { try JSONDecoder().decode(Self.self,from:JSONEncoder().encode(value)) }
    func data() throws -> Data { let e=JSONEncoder();e.outputFormatting=[.sortedKeys];return try e.encode(self) }
}
struct MotionCloudFailure: LocalizedError {
    var status: Int
    var message: String
    var errorDescription: String? { message }
    var retryable: Bool { status == 408 || status == 429 || status >= 500 }
}
struct MotionCloudCredential: Codable {
    var endpoint: String
    var accountId: String
    var token: String
    var scope: String { MotionCloudAPI.hash(Data((endpoint+"\n"+accountId).utf8)) }
}
enum MotionCloudKeychain {
    private static let base: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"MotionLab.Cloud",kSecAttrAccount as String:"active"]
    static func read() throws -> MotionCloudCredential? {
        var query=base;query[kSecReturnData as String]=true;query[kSecMatchLimit as String]=kSecMatchLimitOne
        var result:CFTypeRef?;let status=SecItemCopyMatching(query as CFDictionary,&result)
        if status == errSecItemNotFound {return nil}
        guard status == errSecSuccess,let data=result as? Data else {throw MotionCloudFailure(status:0,message:"无法读取安全连接凭据（\(status)）")}
        return try JSONDecoder().decode(MotionCloudCredential.self,from:data)
    }
    static func save(_ credential:MotionCloudCredential) throws {
        let data=try JSONEncoder().encode(credential)
        var status=SecItemUpdate(base as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if status == errSecItemNotFound {
            var item=base;item[kSecValueData as String]=data;item[kSecAttrAccessible as String]=kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status=SecItemAdd(item as CFDictionary,nil)
        }
        guard status == errSecSuccess else {throw MotionCloudFailure(status:0,message:"无法保存安全连接凭据（\(status)）")}
    }
    static func remove() throws {
        let status=SecItemDelete(base as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {throw MotionCloudFailure(status:0,message:"无法移除连接凭据")}
    }
}
private final class NoCloudRedirect: NSObject,URLSessionTaskDelegate {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void) {completionHandler(nil)}
}
final class MotionCloudAPI {
    let credential:MotionCloudCredential
    private let session:URLSession
    init(_ credential:MotionCloudCredential) throws {
        _=try Self.endpoint(credential.endpoint)
        guard credential.token.range(of:"^[A-Za-z0-9_-]{32,200}$",options:.regularExpression) != nil else {throw MotionCloudFailure(status:0,message:"访问令牌格式不正确")}
        self.credential=credential
        let config=URLSessionConfiguration.ephemeral;config.timeoutIntervalForRequest=60;config.timeoutIntervalForResource=600
        session=URLSession(configuration:config,delegate:NoCloudRedirect(),delegateQueue:nil)
    }
    deinit {session.invalidateAndCancel()}
    static func endpoint(_ raw:String) throws -> String {
        let raw=raw.trimmingCharacters(in:.whitespacesAndNewlines)
        guard let c=URLComponents(string:raw),c.scheme == "https",let host=c.host,!host.isEmpty,c.user == nil,c.password == nil,c.query == nil,c.fragment == nil,c.path.isEmpty || c.path == "/" else {throw MotionCloudFailure(status:0,message:"请输入 HTTPS 服务器地址，不含路径或账号")}
        return raw.hasSuffix("/") ? String(raw.dropLast()) : raw
    }
    static func hash(_ data:Data)->String { SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined() }
    static func fileHash(_ url:URL)throws->String {
        let file=try FileHandle(forReadingFrom:url);defer{try? file.close()};var h=SHA256()
        while let data=try file.read(upToCount:65536),!data.isEmpty {h.update(data:data)}
        return h.finalize().map{String(format:"%02x",$0)}.joined()
    }
    func download(_ path:String,to destination:URL,expectedHash:String) async throws {
        guard path.hasPrefix("/v1/"),expectedHash.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil,let url=URL(string:credential.endpoint+path) else {throw MotionCloudFailure(status:0,message:"文件下载参数无效")}
        var request=URLRequest(url:url);request.setValue("Bearer "+credential.token,forHTTPHeaderField:"Authorization")
        let (temporary,response)=try await session.download(for:request)
        defer{try? FileManager.default.removeItem(at:temporary)}
        guard let http=response as? HTTPURLResponse,(200...299).contains(http.statusCode) else {throw MotionCloudFailure(status:(response as? HTTPURLResponse)?.statusCode ?? 0,message:"原始文件不可下载，可能已归档")}
        let size=try temporary.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard size>0,size<=300*1024*1024,try Self.fileHash(temporary) == expectedHash else {throw MotionCloudFailure(status:0,message:"下载文件校验失败")}
        if FileManager.default.fileExists(atPath:destination.path) {guard try Self.fileHash(destination) == expectedHash else {throw MotionCloudFailure(status:0,message:"目标文件已有不同内容")};return}
        try FileManager.default.moveItem(at:temporary,to:destination)
    }
    func request(_ path:String,method:String="GET",body:CloudJSON?=nil,file:URL?=nil,sha:String?=nil) async throws -> CloudJSON {
        guard path.hasPrefix("/v1/"),let url=URL(string:credential.endpoint+path) else {throw MotionCloudFailure(status:0,message:"无效请求地址")}
        var request=URLRequest(url:url);request.httpMethod=method;request.setValue("Bearer "+credential.token,forHTTPHeaderField:"Authorization")
        let data:Data;let response:URLResponse
        if let file {
            let size=(try file.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
            guard size>0,size<=300*1024*1024,let sha else {throw MotionCloudFailure(status:0,message:"文件为空或超过 300 MB")}
            request.setValue("application/octet-stream",forHTTPHeaderField:"Content-Type");request.setValue(sha,forHTTPHeaderField:"X-Content-SHA256")
            (data,response)=try await session.upload(for:request,fromFile:file)
        } else {
            if let body {let payload=try body.data();guard payload.count<=8*1024*1024 else {throw MotionCloudFailure(status:0,message:"报告超过 8 MB")};request.httpBody=payload;request.setValue("application/json",forHTTPHeaderField:"Content-Type")}
            (data,response)=try await session.data(for:request)
        }
        guard let http=response as? HTTPURLResponse else {throw MotionCloudFailure(status:0,message:"服务器响应无效")}
        guard (200...299).contains(http.statusCode) else {
            let messages=[401:"访问令牌失效，请重新连接",403:"没有访问权限",409:"云端记录冲突或已归档；本机数据已保留",413:"文件超出大小限制",422:"数据格式或校验失败",429:"请求频繁，请稍后重试",507:"服务器存储空间不足"]
            throw MotionCloudFailure(status:http.statusCode,message:messages[http.statusCode] ?? "服务器请求失败（\(http.statusCode)）")
        }
        guard data.count<=16*1024*1024 else {throw MotionCloudFailure(status:0,message:"服务器响应过大")}
        return try JSONDecoder().decode(CloudJSON.self,from:data)
    }
}
struct MotionCloudUpload:Codable,Identifiable {
    var id:String
    var localId:UUID
    var metadata:CloudJSON
    var report:CloudJSON?
    var artifacts:[String:String]
    var hashes:[String:String]
    var status="pending"
    var message="等待上传"
}
struct MotionCloudState:Codable {
    var cursor=0
    var uploads:[MotionCloudUpload]=[]
    var records:[String:CloudJSON]=[:]
}
@MainActor final class MotionCloud:ObservableObject {
    @Published var credential:MotionCloudCredential?
    @Published var state=MotionCloudState()
    @Published var busy=false
    @Published var message=""
    private var operation:Task<Void,Never>?
    private let directory:URL
    var scope:String? {credential?.scope}
    init() {
        directory=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("MotionCloud",isDirectory:true)
        do {try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);credential=try MotionCloudKeychain.read();try load()}
        catch {message="连接状态读取失败：\(error.localizedDescription)"}
    }
    private func folder() throws -> URL {
        guard let scope else {throw MotionCloudFailure(status:0,message:"请先连接服务器")}
        let url=directory.appendingPathComponent(scope,isDirectory:true);try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);return url
    }
    private func load()throws {
        state=MotionCloudState();guard credential != nil else{return}
        let url=try folder().appendingPathComponent("state.json")
        if FileManager.default.fileExists(atPath:url.path) {state=try JSONDecoder().decode(MotionCloudState.self,from:Data(contentsOf:url))}
        for i in state.uploads.indices where state.uploads[i].status == "uploading" {state.uploads[i].status="pending";state.uploads[i].message="上次上传中断，可重试"}
    }
    private func save()throws {try JSONEncoder().encode(state).write(to:folder().appendingPathComponent("state.json"),options:.atomic)}
    func connect(endpoint:String,secret:String) async {
        guard !busy else{return};busy=true;defer{busy=false}
        do {
            var token=secret.trimmingCharacters(in:.whitespacesAndNewlines);var claimed:String?
            if token.hasPrefix("{") {let parsed=try JSONDecoder().decode(CloudJSON.self,from:Data(token.utf8));claimed=parsed["accountId"].string;token=parsed["token"].string ?? ""}
            var candidate=MotionCloudCredential(endpoint:try MotionCloudAPI.endpoint(endpoint),accountId:"",token:token)
            let api=try MotionCloudAPI(candidate);let identity=try await api.request("/v1/me")
            guard let account=identity["accountId"].string,!account.isEmpty,claimed == nil || claimed == account else {throw MotionCloudFailure(status:0,message:"凭据账户与服务器身份不一致")}
            candidate.accountId=account
            try MotionCloudKeychain.save(candidate);credential=candidate;try load();message="已验证并连接"
        } catch {message=error.localizedDescription}
    }
    func disconnect() {
        guard !busy else{return}
        do {try MotionCloudKeychain.remove();credential=nil;state=MotionCloudState();message="已断开，云端队列保留在本机"}catch{message=error.localizedDescription}
    }
    /// Freeze files and metadata before first network mutation, keeping exact retries safe.
    func enqueue(localId:UUID,metadata:CloudJSON,report:CloudJSON?,artifacts:[String:URL]) throws {
        guard !busy else {throw MotionCloudFailure(status:0,message:"同步进行中，请稍后添加")}
        var hashes:[String:String]=[:]
        for (name,url) in artifacts {hashes[name]=try MotionCloudAPI.fileHash(url)}
        let fingerprint=try CloudJSON.object(["metadata":metadata,"report":report ?? .null,"hashes":.object(hashes.mapValues{.string($0)})]).data()
        let id=localId.uuidString.lowercased()+"-"+MotionCloudAPI.hash(fingerprint).prefix(16)
        if state.uploads.contains(where:{$0.id == id}) {return}
        let target=try folder().appendingPathComponent(id,isDirectory:true);try FileManager.default.createDirectory(at:target,withIntermediateDirectories:true)
        var files:[String:String]=[:]
        for (name,url) in artifacts {
            let destination=target.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath:destination.path) {try FileManager.default.copyItem(at:url,to:destination)}
            guard try MotionCloudAPI.fileHash(destination) == hashes[name] else {throw MotionCloudFailure(status:0,message:"上传快照校验失败")}
            files[name]=id+"/"+name
        }
        state.uploads.append(MotionCloudUpload(id:id,localId:localId,metadata:metadata,report:report,artifacts:files,hashes:hashes));try save()
    }
    func download(recordId:String,name:String,to destination:URL) async throws {
        guard !busy,let credential,let record=state.records[recordId] else {throw MotionCloudFailure(status:0,message:"当前无法下载")}
        guard recordId.range(of:"^[A-Za-z0-9_-]{1,128}$",options:.regularExpression) != nil,["video.mp4","imu.csv","imu.zip"].contains(name),let artifact=record["artifacts"].array.first(where:{$0["name"].string == name}),let hash=artifact["sha256"].string else {throw MotionCloudFailure(status:0,message:"云端没有可用原始文件")}
        busy=true;defer{busy=false}
        try await MotionCloudAPI(credential).download("/v1/records/"+recordId+"/artifacts/"+name,to:destination,expectedHash:hash)
    }
    func pause(){operation?.cancel();message="正在暂停"}
    func sync() {
        guard !busy,let credential else{return};busy=true
        operation=Task {
            defer{busy=false;operation=nil}
            do {
                let api=try MotionCloudAPI(credential)
                let identity=try await api.request("/v1/me")
                guard identity["accountId"].string == credential.accountId else {throw MotionCloudFailure(status:401,message:"账户身份已变化，请重新连接")}
                let root=try folder()
                for i in state.uploads.indices where state.uploads[i].status != "complete" && state.uploads[i].status != "blocked" {
                    try Task.checkCancellation()
                    let upload=state.uploads[i];state.uploads[i].status="uploading";state.uploads[i].message="上传中";try save()
                    do {
                        let path="/v1/records/"+upload.id
                        _=try await retry {try await api.request(path,method:"PUT",body:upload.metadata)}
                        for name in upload.artifacts.keys.sorted() {
                            try Task.checkCancellation();state.uploads[i].message="上传 \(name)"
                            let file=root.appendingPathComponent(upload.artifacts[name]!)
                            guard try MotionCloudAPI.fileHash(file) == upload.hashes[name] else {throw MotionCloudFailure(status:0,message:"本机上传快照已改变")}
                            _=try await retry {try await api.request(path+"/artifacts/"+name,method:"PUT",file:file,sha:upload.hashes[name])}
                        }
                        if let report=upload.report {_=try await retry {try await api.request(path+"/client-report",method:"PUT",body:report)}}
                        var commit:[String:CloudJSON]=["artifacts":.object(upload.hashes.mapValues{.string($0)})]
                        if let report=upload.report {commit["reportVersion"]=report["version"]}
                        _=try await retry {try await api.request(path+"/complete",method:"POST",body:.object(commit))}
                        state.uploads[i].status="complete";state.uploads[i].message="已上传";try save()
                    }catch{
                        let cancelled=Task.isCancelled || error is CancellationError
                        let failure=error as? MotionCloudFailure
                        state.uploads[i].status=cancelled ? "pending" : failure != nil && !failure!.retryable ? "blocked" : "pending"
                        state.uploads[i].message=cancelled ? "已暂停，可继续" : error.localizedDescription
                        try save()
                        if cancelled || failure?.status == 401 {throw error}
                    }
                }
                var more=true
                while more {
                    try Task.checkCancellation()
                    let page=try await api.request("/v1/records?after=\(state.cursor)&limit=100")
                    var merged=state.records
                    for record in page["records"].array {
                        guard let id=record["record_id"].string,id.range(of:"^[A-Za-z0-9_-]{1,128}$",options:.regularExpression) != nil else {throw MotionCloudFailure(status:0,message:"云端记录标识无效")}
                        merged[id]=try await api.request("/v1/records/"+id)
                    }
                    for id in page["archivedRecordIds"].array.compactMap(\.string) {merged.removeValue(forKey:id)}
                    guard let next=page["nextCursor"].number,next>=Double(state.cursor),!page["hasMore"].bool || next>Double(state.cursor) else {throw MotionCloudFailure(status:0,message:"云端同步游标无效")}
                    state.records=merged;state.cursor=Int(next);try save();more=page["hasMore"].bool
                }
                message="同步完成，\(state.records.count) 条云端记录"
            }catch{message=Task.isCancelled ? "同步已暂停，本机队列已保留" : error.localizedDescription}
        }
    }
    private func retry<T>(_ action:()async throws->T)async throws->T {
        for attempt in 0..<3 {
            try Task.checkCancellation()
            do{return try await action()}catch{
                if Task.isCancelled {throw CancellationError()}
                let retryable=(error as? MotionCloudFailure)?.retryable ?? (error is URLError)
                if !retryable || attempt == 2 {throw error}
                try await Task.sleep(nanoseconds:UInt64(attempt+1)*1_000_000_000)
            }
        }
        throw CancellationError()
    }
}
