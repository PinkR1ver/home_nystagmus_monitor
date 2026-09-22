import Foundation

@main struct EyeRegionSmoke {
    static func main() throws {
        let region = EyeRegion(x: 0.2, y: 0.35, width: 0.6, height: 0.3)
        precondition(region.isValid)
        precondition(region.pixelRect(width: 1000, height: 600) == CGRect(x: 200, y: 210, width: 600, height: 180))
        precondition(!EyeRegion(x: .nan).isValid)
        precondition(!EyeRegion(x: 0.9, width: 0.2).isValid)
        precondition(EyeRegion(x: 0, y: 0, width: 1, height: 1).pixelRect(width: 1920, height: 1080) == CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let restored = try JSONDecoder().decode(EyeRegion.self, from: JSONEncoder().encode(region))
        precondition(restored == region)
        print("PASS: normalized top-left ROI, bounds, full frame and persisted selection")
    }
}
