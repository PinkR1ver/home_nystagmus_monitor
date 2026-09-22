import Foundation

@main struct IMUWriterSmoke {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = IMUSession(id: UUID(), startedAt: Date(), startElapsedNs: 1_000_000_000, options: IMUOptions())
        let writer = try IMUFileWriter(directory: folder, session: session)
        try writer.append(sensor: "accelerometer", timestampNs: 1_010_000_000, receivedNs: 1_011_000_000, x: 0, y: 0, z: -9.80665)
        try writer.append(sensor: "accelerometer", timestampNs: 1_210_000_000, receivedNs: 1_211_000_000, x: 1, y: 2, z: 3)
        try writer.append(sensor: "gyroscope", timestampNs: 1_010_000_000, receivedNs: 1_011_000_000, x: .nan, y: 0, z: 0)
        try writer.marker(nowNs: 1_500_000_000, label: "user_marker")
        let completed = try writer.finish(nowNs: 2_000_000_000, reason: "app_inactive")
        precondition(completed.status == "interrupted")
        precondition(completed.durationS == 1)
        precondition(completed.summaries["accelerometer"]?.count == 2)
        precondition(completed.summaries["accelerometer"]?.gapsOver100Ms == 1)
        precondition(completed.summaries["gyroscope"]?.invalid == 1)
        let data = try Data(contentsOf: folder.appendingPathComponent(session.metadataName))
        let restored = try JSONDecoder().decode(IMUSession.self, from: data)
        precondition(restored.id == session.id && restored.status == "interrupted")
        let csv = try String(contentsOf: folder.appendingPathComponent(session.fileName), encoding: .utf8)
        precondition(csv.components(separatedBy: "\n").count == 4)
        precondition(csv.contains("accelerometer,1010000000,1011000000,0.01,0.0,0.0,-9.80665,-1"))
        let marker = try String(contentsOf: folder.appendingPathComponent(session.markersName), encoding: .utf8)
        precondition(marker.contains("1500000000,0.5,user_marker"))
        print("PASS: Android CSV schema, SI data, invalid sample rejection, gap stats, markers and interrupted-session persistence")
    }
}
