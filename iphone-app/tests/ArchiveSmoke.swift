import Foundation
@main struct ArchiveSmoke {
    static func main()throws {
        let folder=URL(fileURLWithPath:"/tmp/motion-archive-smoke",isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let csv=folder.appendingPathComponent("source.csv");try Data("time_s,value\n0,1\n".utf8).write(to:csv)
        let empty=folder.appendingPathComponent("empty.json");try Data("{}".utf8).write(to:empty)
        let output=folder.appendingPathComponent("result.zip");try? FileManager.default.removeItem(at:output)
        try MotionArchive.write(files:["signals.csv":csv,"报告.json":empty],to:output)
        do{try MotionArchive.write(files:["../escape":csv],to:folder.appendingPathComponent("bad.zip"));fatalError("unsafe entry accepted")}catch{}
        precondition(MotionArchive.csvCell("a,\"b") == "\"a,\"\"b\"")
        print(output.path)
    }
}
