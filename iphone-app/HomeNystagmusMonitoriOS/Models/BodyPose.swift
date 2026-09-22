import Foundation

struct BodyVector: Codable, Equatable {
    var x: Double; var y: Double; var z: Double
    init(_ x: Double, _ y: Double, _ z: Double) { self.x=x; self.y=y; self.z=z }
    static func + (a: Self, b: Self) -> Self { Self(a.x+b.x,a.y+b.y,a.z+b.z) }
    static func - (a: Self, b: Self) -> Self { Self(a.x-b.x,a.y-b.y,a.z-b.z) }
    static func * (a: Self, b: Double) -> Self { Self(a.x*b,a.y*b,a.z*b) }
    func dot(_ b: Self) -> Double { x*b.x+y*b.y+z*b.z }
    func cross(_ b: Self) -> Self { Self(y*b.z-z*b.y,z*b.x-x*b.z,x*b.y-y*b.x) }
    var norm: Double { sqrt(dot(self)) }
    var finite: Bool { x.isFinite && y.isFinite && z.isFinite }
    func unit() throws -> Self {
        guard norm > 1e-8, norm.isFinite else { throw BodyAnalysisError.unavailable("身体坐标轴不可用") }
        return self * (1/norm)
    }
}
struct BodyPoseFrame: Codable {
    var timeMs: Int
    var points: [BodyVector]
    var scores: [Double]
    var personCount: Int
    var imagePoints: [BodyVector] = []
}
struct BodySubject: Codable {
    var massKg = 67.0
    var heightCm = 173.0
    var profile = "M"
}
enum BodyAnalysisError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? { if case .unavailable(let message) = self { return message }; return nil }
}

struct BodySegmentParameter: Codable {
    var mass_fraction: Double
    var com_fraction: Double
    var gyration_xyz: [Double]
}
struct BodySegmentConfig: Codable {
    var profiles: [String: [String: BodySegmentParameter]]
    var fixed_inertia_lengths_m: [String: Double]
}
struct BodySignal: Codable {
    var timeS: Double
    var inertia: Double?
    var pelvisZ: Double?
    var comZ: Double?
    var kneeL: Double?
    var kneeR: Double?
    var hipL: Double?
    var hipR: Double?
    var trunk: Double?
    var quality: Double
}
struct BodyStats: Codable {
    var n: Int
    var mean: Double?
    var sd: Double?
    var cvPercent: Double?
}
struct BodyEvent: Codable {
    var direction: String
    var start: Int
    var end: Int
    var startS: Double
    var endS: Double
    var status: String
    var reason: String
    var metrics: [String: Double?] = [:]
}
enum BodyNumbers {
    static func percentile(_ values: [Double], _ p: Double) -> Double? {
        let a = values.filter(\.isFinite).sorted()
        guard !a.isEmpty else { return nil }
        let i = Double(a.count - 1) * min(1, max(0,p))
        let lo = Int(floor(i)); let hi = Int(ceil(i))
        return a[lo] + (a[hi]-a[lo]) * (i-Double(lo))
    }
    static func median(_ a: [Double]) -> Double? { percentile(a, 0.5) }
    static func stats(_ values: [Double?], cv: Bool = true) -> BodyStats {
        let a = values.compactMap { $0 }.filter(\.isFinite)
        guard !a.isEmpty else { return BodyStats(n: 0) }
        let mean = a.reduce(0,+)/Double(a.count)
        let sd: Double? = a.count > 1 ? sqrt(a.reduce(0) { $0 + pow($1-mean,2) } / Double(a.count-1)) : nil
        let variation = cv && mean > 1e-8 && a.allSatisfy { $0 >= 0 } ? sd.map { 100*$0/mean } : nil
        return BodyStats(n: a.count, mean: mean, sd: sd, cvPercent: variation)
    }
    static func angle(_ a: BodyVector, _ b: BodyVector, _ c: BodyVector) -> Double? {
        let u=a-b; let v=c-b; let n=u.norm*v.norm
        return n < 1e-8 ? nil : 180-acos(min(1,max(-1,u.dot(v)/n)))*180 / .pi
    }
}
