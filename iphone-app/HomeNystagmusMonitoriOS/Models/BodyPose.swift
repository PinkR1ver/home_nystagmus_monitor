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
