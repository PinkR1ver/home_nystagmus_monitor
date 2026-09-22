import AppKit
import CoreML
import Foundation
import Vision

struct Benchmark {
  let name: String
  let modelPath: String
  let imagePath: String
}

func percentile(_ values: [Double], fraction: Double) -> Double {
  let sorted = values.sorted()
  let index = min(
    sorted.count - 1,
    max(0, Int((Double(sorted.count - 1) * fraction).rounded()))
  )
  return sorted[index]
}

func loadImage(at path: String) throws -> CGImage {
  guard
    let image = NSImage(contentsOfFile: path),
    let cgImage = image.cgImage(
      forProposedRect: nil,
      context: nil,
      hints: nil
    )
  else {
    throw NSError(
      domain: "RehabBenchmark",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Cannot load image: \(path)"]
    )
  }
  return cgImage
}

func loadModel(at path: String) throws -> VNCoreMLModel {
  let compiledURL = try MLModel.compileModel(
    at: URL(fileURLWithPath: path)
  )
  let configuration = MLModelConfiguration()
  configuration.computeUnits = .all
  let model = try MLModel(
    contentsOf: compiledURL,
    configuration: configuration
  )
  return try VNCoreMLModel(for: model)
}

func run(_ benchmark: Benchmark, iterations: Int) throws {
  let model = try loadModel(at: benchmark.modelPath)
  let image = try loadImage(at: benchmark.imagePath)
  let request = VNCoreMLRequest(model: model)
  request.imageCropAndScaleOption = .scaleFill
  var measured: [Double] = []
  var resultDescription = "no output"

  for index in 0..<(iterations + 2) {
    let handler = VNImageRequestHandler(
      cgImage: image,
      orientation: .up,
      options: [:]
    )
    let startedAt = CFAbsoluteTimeGetCurrent()
    try handler.perform([request])
    let elapsed = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
    if index >= 2 {
      measured.append(elapsed)
    }

    if let feature = request.results?
      .compactMap({ $0 as? VNCoreMLFeatureValueObservation })
      .first,
      let array = feature.featureValue.multiArrayValue
    {
      let sample = (0..<min(7, array.count))
        .map { String(format: "%.3f", array[$0].doubleValue) }
        .joined(separator: ",")
      resultDescription =
        "\(feature.featureName) shape=\(array.shape) sample=[\(sample)]"
    }
  }

  let median = percentile(measured, fraction: 0.5)
  let p95 = percentile(measured, fraction: 0.95)
  print(
    "\(benchmark.name): median=\(String(format: "%.1f", median))ms "
      + "p95=\(String(format: "%.1f", p95))ms "
      + "iterations=\(measured.count) output=\(resultDescription)"
  )
}

guard CommandLine.arguments.count == 6 else {
  FileHandle.standardError.write(
    Data(
      """
      usage: benchmark_coreml.swift \
      <YOLO.mlpackage> <body-image> <HeadPose.mlpackage> <face-image> <iterations>

      """.utf8
    )
  )
  exit(64)
}

let iterations = max(1, Int(CommandLine.arguments[5]) ?? 10)
let benchmarks = [
  Benchmark(
    name: "YOLO11nPose",
    modelPath: CommandLine.arguments[1],
    imagePath: CommandLine.arguments[2]
  ),
  Benchmark(
    name: "FCQHeadPose",
    modelPath: CommandLine.arguments[3],
    imagePath: CommandLine.arguments[4]
  ),
]

do {
  for benchmark in benchmarks {
    try run(benchmark, iterations: iterations)
  }
} catch {
  FileHandle.standardError.write(
    Data("benchmark failed: \(error)\n".utf8)
  )
  exit(1)
}
