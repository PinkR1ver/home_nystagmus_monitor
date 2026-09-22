import Foundation

struct IMUOptions: Codable {
    var participant = ""
    var pocket = "right_front"
    var limitMinutes = 5
    var phoneTop = "up"
    var screenFacing = "body"
    var note = ""
}
struct IMUSensorSummary: Codable {
    var count = 0
    var firstNs: Int64?
    var lastNs: Int64?
    var maxGapMs = 0.0
    var gapsOver100Ms = 0
    var nonIncreasing = 0
    var invalid = 0
}
struct IMUSession: Codable, Identifiable {
    var id: UUID
    var startedAt: Date
    var startElapsedNs: Int64
    var durationS = 0.0
    var options: IMUOptions
    var status = "recording"
    var stopReason: String?
    var summaries: [String: IMUSensorSummary] = ["accelerometer": IMUSensorSummary(), "gyroscope": IMUSensorSummary()]
    var fileName: String { id.uuidString + "-imu.csv" }
    var metadataName: String { id.uuidString + "-imu.json" }
    var markersName: String { id.uuidString + "-markers.csv" }
}

/// Serial queue only. Streams raw samples to disk with the Android CSV column convention.
final class IMUFileWriter {
    private(set) var session: IMUSession
    private let directory: URL
    private let samples: FileHandle
    private let markers: FileHandle
    private var closed = false
    init(directory: URL, session: IMUSession) throws {
        self.directory = directory
        self.session = session
        let samplesURL = directory.appendingPathComponent(session.fileName)
        let markersURL = directory.appendingPathComponent(session.markersName)
        try Data("sensor,sensor_timestamp_ns,received_elapsed_ns,relative_s,x,y,z,accuracy\n".utf8).write(to: samplesURL, options: .atomic)
        try Data("elapsed_ns,relative_s,label\n".utf8).write(to: markersURL, options: .atomic)
        samples = try FileHandle(forWritingTo: samplesURL)
        markers = try FileHandle(forWritingTo: markersURL)
        try samples.seekToEnd(); try markers.seekToEnd()
        try checkpoint(nowNs: session.startElapsedNs)
    }
    func append(sensor: String, timestampNs: Int64, receivedNs: Int64, x: Double, y: Double, z: Double) throws {
        guard !closed, var stats = session.summaries[sensor] else { return }
        guard [x,y,z].allSatisfy(\.isFinite), timestampNs >= session.startElapsedNs else {
            stats.invalid += 1; session.summaries[sensor] = stats; return
        }
        if let last = stats.lastNs {
            let gap = Double(timestampNs-last)/1e6
            stats.maxGapMs = max(stats.maxGapMs, gap)
            if gap > 100 { stats.gapsOver100Ms += 1 }
            if timestampNs <= last { stats.nonIncreasing += 1 }
        }
        stats.count += 1
        stats.firstNs = stats.firstNs ?? timestampNs
        stats.lastNs = timestampNs
        session.summaries[sensor] = stats
        let relative = Double(timestampNs-session.startElapsedNs)/1e9
        // -1: Core Motion raw streams do not expose Android sensor accuracy codes.
        let line = "\(sensor),\(timestampNs),\(receivedNs),\(relative),\(x),\(y),\(z),-1\n"
        try samples.write(contentsOf: Data(line.utf8))
    }
    func marker(nowNs: Int64, label: String) throws {
        guard !closed, label.range(of: "^[a-z0-9_]+$", options: .regularExpression) != nil else { return }
        try markers.write(contentsOf: Data("\(nowNs),\(Double(nowNs-session.startElapsedNs)/1e9),\(label)\n".utf8))
    }
    func checkpoint(nowNs: Int64) throws {
        session.durationS = max(0, Double(nowNs-session.startElapsedNs)/1e9)
        try samples.synchronize(); try markers.synchronize()
        try JSONEncoder().encode(session).write(to: directory.appendingPathComponent(session.metadataName), options: .atomic)
    }
    func finish(nowNs: Int64, reason: String) throws -> IMUSession {
        if closed { return session }
        defer { closed = true; try? samples.close(); try? markers.close() }
        session.status = reason == "user" || reason == "time_limit" ? "completed" : "interrupted"
        session.stopReason = reason
        try checkpoint(nowNs: nowNs)
        return session
    }
    deinit { try? samples.close(); try? markers.close() }
}

