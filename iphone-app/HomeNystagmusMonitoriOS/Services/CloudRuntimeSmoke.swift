#if DEBUG
import Foundation

@MainActor enum CloudRuntimeSmoke {
    static func run() async {
        let documents=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        let credentialFile=documents.appendingPathComponent("cloud-smoke-credential.json")
        let resultFile=documents.appendingPathComponent("cloud-smoke-result.json")
        var result:[String:CloudJSON]=[:]
        do {
            let secret=try String(contentsOf:credentialFile,encoding:.utf8)
            let cloud=MotionCloud()
            await cloud.connect(endpoint:"https://39.107.192.82",secret:secret)
            try? FileManager.default.removeItem(at:credentialFile)
            guard let credential=cloud.credential else {throw MotionCloudFailure(status:0,message:cloud.message)}
            let restored=try MotionCloudKeychain.read()
            guard restored?.accountId == credential.accountId else {throw MotionCloudFailure(status:0,message:"Keychain restore mismatch")}
            result["keychainRestored"] = .bool(true)
            let id=UUID();let csv=documents.appendingPathComponent("cloud-smoke-imu.csv")
            try Data("sensor,sensor_timestamp_ns,received_elapsed_ns,relative_s,x,y,z,accuracy\naccelerometer,1000000000,1001000000,0.0,0.0,0.0,9.80665,-1\ngyroscope,1000000000,1001000000,0.0,0.0,0.0,0.0,-1\n".utf8).write(to:csv,options:.atomic)
            let metadata=CloudJSON.object(["schemaVersion":.number(1),"taskType":.string("imu"),"startedAt":.string(ISO8601DateFormatter().string(from:Date())),"durationSec":.number(1),"device":.object(["platform":.string("ios-simulator")]),"context":.object(["syntheticAcceptance":.bool(true)]),"subjectId":.null])
            try cloud.enqueue(localId:id,metadata:metadata,report:nil,artifacts:["imu.csv":csv])
            try cloud.enqueue(localId:id,metadata:metadata,report:nil,artifacts:["imu.csv":csv])
            guard cloud.state.uploads.filter({$0.localId == id}).count == 1 else {throw MotionCloudFailure(status:0,message:"Duplicate queue entry")}
            cloud.sync()
            while cloud.busy {try await Task.sleep(nanoseconds:100_000_000)}
            guard let item=cloud.state.uploads.first(where:{$0.localId == id}),item.status == "complete",cloud.state.records[item.id] != nil else {throw MotionCloudFailure(status:0,message:"Sync failed: "+cloud.message)}
            result["recordId"] = .string(item.id);result["uploadedAndPulled"] = .bool(true)
            let api=try MotionCloudAPI(credential)
            _=try await api.request("/v1/records/"+item.id,method:"PUT",body:metadata)
            _=try await api.request("/v1/records/"+item.id+"/artifacts/imu.csv",method:"PUT",file:csv,sha:MotionCloudAPI.fileHash(csv))
            result["idempotentRetry"] = .bool(true)
            let downloaded=documents.appendingPathComponent("cloud-smoke-downloaded.csv")
            try? FileManager.default.removeItem(at:downloaded)
            try await cloud.download(recordId:item.id,name:"imu.csv",to:downloaded)
            guard try MotionCloudAPI.fileHash(downloaded) == MotionCloudAPI.fileHash(csv) else {throw MotionCloudFailure(status:0,message:"Downloaded bytes mismatch")}
            try FileManager.default.removeItem(at:downloaded)
            result["downloadSHA256Verified"] = .bool(true)
            var invalid=credential;invalid.token=String(repeating:"x",count:40)
            do {_=try await MotionCloudAPI(invalid).request("/v1/me");throw MotionCloudFailure(status:0,message:"Invalid token accepted")}
            catch let failure as MotionCloudFailure {guard failure.status == 401 else {throw failure}}
            result["unauthorizedRejected"] = .bool(true)
            _=try await api.request("/v1/records/"+item.id+"/archive",method:"POST")
            cloud.sync();while cloud.busy {try await Task.sleep(nanoseconds:100_000_000)}
            guard cloud.state.records[item.id] == nil else {throw MotionCloudFailure(status:0,message:"Archive tombstone not applied")}
            result["archiveTombstoneMerged"] = .bool(true)
            let reloaded=MotionCloud()
            guard reloaded.state.cursor == cloud.state.cursor,reloaded.state.uploads.contains(where:{$0.id == item.id && $0.status == "complete"}) else {throw MotionCloudFailure(status:0,message:"Queue persistence mismatch")}
            result["queueRestored"] = .bool(true)
            cloud.disconnect();try? FileManager.default.removeItem(at:csv)
            result["passed"] = .bool(true)
        }catch {result["passed"] = .bool(false);result["error"] = .string(error.localizedDescription)}
        try? CloudJSON.object(result).data().write(to:resultFile,options:.atomic)
    }
}
#endif
