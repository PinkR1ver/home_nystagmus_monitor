import Foundation
import CoreMotion
import SwiftUI

@MainActor final class IMUCapture: ObservableObject {
    @Published var active = false
    @Published var finishing = false
    @Published var duration = 0.0
    @Published var sampleCount = 0
    @Published var error: String?
    private let motion = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1; queue.name = "motion.imu.writer"; return queue
    }()
    private var writer: IMUFileWriter?
    private var timer: Timer?
    private var completion: ((IMUSession) -> Void)?
    static var nowNs: Int64 { Int64(ProcessInfo.processInfo.systemUptime * 1e9) }
    var available: Bool { motion.isAccelerometerAvailable && motion.isGyroAvailable }

    func start(directory: URL, options: IMUOptions, completion: @escaping (IMUSession) -> Void) {
        guard !active, !finishing else { return }
        guard available else { error = "此设备没有可用的加速度计或陀螺仪，请使用真机采集。"; return }
        do {
            let session = IMUSession(id: UUID(), startedAt: Date(), startElapsedNs: Self.nowNs, options: options)
            let writer = try IMUFileWriter(directory: directory, session: session)
            self.writer = writer; self.completion = completion
            active = true; error = nil; duration = 0; sampleCount = 0
            motion.accelerometerUpdateInterval = 0.01
            motion.gyroUpdateInterval = 0.01
            // Core Motion acceleration is in g. Export m/s² like Android, with gravity included.
            motion.startAccelerometerUpdates(to: queue) { [weak self] data, failure in
                do {
                    if let failure { throw failure }
                    if let data {
                        try writer.append(sensor: "accelerometer", timestampNs: Int64(data.timestamp*1e9), receivedNs: Int64(ProcessInfo.processInfo.systemUptime*1e9), x: data.acceleration.x*9.80665, y: data.acceleration.y*9.80665, z: data.acceleration.z*9.80665)
                    }
                } catch { let message = error.localizedDescription; Task { @MainActor in self?.fail(message) } }
            }
            motion.startGyroUpdates(to: queue) { [weak self] data, failure in
                do {
                    if let failure { throw failure }
                    if let data {
                        try writer.append(sensor: "gyroscope", timestampNs: Int64(data.timestamp*1e9), receivedNs: Int64(ProcessInfo.processInfo.systemUptime*1e9), x: data.rotationRate.x, y: data.rotationRate.y, z: data.rotationRate.z)
                    }
                } catch { let message = error.localizedDescription; Task { @MainActor in self?.fail(message) } }
            }
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkpoint(limit: options.limitMinutes*60) }
            }
        } catch { self.error = error.localizedDescription }
    }
    private func fail(_ message: String) { error = message; stop(reason: "sensor_or_storage_error") }
    private func checkpoint(limit: Int) {
        guard active, let writer else { return }
        let now = Self.nowNs
        queue.addOperation { [weak self] in
            do {
                try writer.checkpoint(nowNs: now)
                let session = writer.session
                Task { @MainActor in
                    self?.duration = session.durationS
                    self?.sampleCount = session.summaries.values.reduce(0) { $0 + $1.count }
                    if session.durationS >= Double(limit) { self?.stop(reason: "time_limit") }
                }
            } catch { let message = error.localizedDescription; Task { @MainActor in self?.fail(message) } }
        }
    }
    func marker() {
        guard active, let writer else { return }
        let now = Self.nowNs
        queue.addOperation { [weak self] in
            do { try writer.marker(nowNs: now, label: "user_marker") }
            catch { let message = error.localizedDescription; Task { @MainActor in self?.fail(message) } }
        }
    }
    func stop(reason: String = "user") {
        guard active, let writer else { return }
        active = false; finishing = true; timer?.invalidate(); timer = nil
        let completed = completion
        motion.stopAccelerometerUpdates(); motion.stopGyroUpdates()
        let now = Self.nowNs
        queue.addOperation { [weak self] in
            do {
                let session = try writer.finish(nowNs: now, reason: reason)
                Task { @MainActor in self?.writer = nil; self?.finishing = false; completed?(session) }
            } catch { let message = error.localizedDescription; Task { @MainActor in self?.finishing = false; self?.writer = nil; self?.error = "保存失败：\(message)" } }
        }
    }
}
