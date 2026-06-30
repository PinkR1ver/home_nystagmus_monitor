import CoreGraphics
import Darwin
import Foundation
import OnnxRuntimeBindings

protocol GazeEstimator {
    var modelName: String { get }
    func estimate(from eyeImage: CGImage) throws -> GazeVector3D
}

enum GazeEstimatorError: LocalizedError {
    case modelNotFound
    case sessionCreationFailed
    case invalidImage
    case inferenceFailed
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "The bundled ONNX gaze model could not be found."
        case .sessionCreationFailed:
            return "The ONNX Runtime session could not be created."
        case .invalidImage:
            return "The eye crop could not be converted into model input."
        case .inferenceFailed:
            return "The ONNX gaze model failed to run."
        case .invalidOutput:
            return "The ONNX gaze model returned an invalid output tensor."
        }
    }
}

final class ONNXRuntimeGazeEstimator: GazeEstimator {
    let modelName = "swinunet_web.onnx"

    private let inputName = "input"
    private let outputName = "output"
    private let inputWidth = 60
    private let inputHeight = 36
    private let channelCount = 3
    private var env: ORTEnv?
    private var ortSession: ORTSession?

    func estimate(from eyeImage: CGImage) throws -> GazeVector3D {
        let session = try activeSession()
        let input = try makeInputTensor(from: eyeImage)
        let inputData = mutableData(from: input)
        let inputTensor = try ORTValue(
            tensorData: inputData,
            elementType: ORTTensorElementDataType.float,
            shape: [1, NSNumber(value: channelCount), NSNumber(value: inputHeight), NSNumber(value: inputWidth)]
        )
        let outputs = try session.run(
            withInputs: [inputName: inputTensor],
            outputNames: Set([outputName]),
            runOptions: nil
        )
        guard let output = outputs[outputName] else {
            throw GazeEstimatorError.inferenceFailed
        }
        let tensorData = try output.tensorData()

        let floatCount = tensorData.length / MemoryLayout<Float>.size
        let base = tensorData.bytes.bindMemory(to: Float.self, capacity: floatCount)
        let values = Array(UnsafeBufferPointer(start: base, count: min(3, floatCount)))
        guard values.count == 3 else {
            throw GazeEstimatorError.invalidOutput
        }

        let x = Double(values[0])
        let y = Double(values[1])
        let zValue = Double(values[2])
        let magnitudeSquared: Double = x * x + y * y + zValue * zValue
        let norm: Double = Swift.max(Darwin.sqrt(magnitudeSquared), 1.0e-8)
        return GazeVector3D(x: x / norm, y: y / norm, z: zValue / norm)
    }

    private func activeSession() throws -> ORTSession {
        if let ortSession {
            return ortSession
        }
        guard let modelURL = Bundle.main.url(forResource: "swinunet_web", withExtension: "onnx") else {
            throw GazeEstimatorError.modelNotFound
        }

        let env = try ORTEnv(loggingLevel: ORTLoggingLevel.warning)
        let options = try ORTSessionOptions()
        try options.setGraphOptimizationLevel(ORTGraphOptimizationLevel.all)
        try options.setIntraOpNumThreads(2)
        let session = try ORTSession(env: env, modelPath: modelURL.path, sessionOptions: options)
        self.env = env
        self.ortSession = session
        return session
    }

    private func makeInputTensor(from image: CGImage) throws -> [Float] {
        let bytesPerPixel = 4
        let bytesPerRow = inputWidth * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: inputWidth * inputHeight * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: &pixels,
            width: inputWidth,
            height: inputHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw GazeEstimatorError.invalidImage
        }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: inputWidth, height: inputHeight))

        var tensor = [Float](repeating: 0, count: channelCount * inputHeight * inputWidth)
        let planeSize = inputHeight * inputWidth
        for y in 0..<inputHeight {
            for x in 0..<inputWidth {
                let pixelOffset = (y * inputWidth + x) * bytesPerPixel
                let tensorOffset = y * inputWidth + x
                tensor[tensorOffset] = Float(pixels[pixelOffset]) / 255.0
                tensor[planeSize + tensorOffset] = Float(pixels[pixelOffset + 1]) / 255.0
                tensor[planeSize * 2 + tensorOffset] = Float(pixels[pixelOffset + 2]) / 255.0
            }
        }
        return tensor
    }

    private func mutableData(from floats: [Float]) -> NSMutableData {
        floats.withUnsafeBufferPointer { buffer in
            NSMutableData(bytes: buffer.baseAddress, length: floats.count * MemoryLayout<Float>.size)
        }
    }
}
