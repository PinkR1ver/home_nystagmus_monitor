# Home Nystagmus Monitor iPhone Prototype

This folder contains a standalone SwiftUI iPhone prototype for demonstrating the device workflow.

## Prototype Scope

- Start camera capture for a short eye video.
- Import an existing video when real nystagmus footage is unavailable.
- Run a local analysis service and show a polished dashboard result.
- Keep analysis state in memory only; no database or account system is included.
- Bundle the Android ONNX model asset at `HomeNystagmusMonitoriOS/Resources/swinunet_web.onnx` so the analysis layer can be replaced with a real iOS runtime later.

## Open

Open `HomeNystagmusMonitoriOS.xcodeproj` in Xcode and run the `HomeNystagmusMonitoriOS` scheme on an iPhone simulator or device.

The current `PrototypeNystagmusAnalysisEngine` is deliberately isolated behind `NystagmusAnalysisEngine`. Replace that implementation when adding ONNX Runtime, Core ML, or a server-backed analysis route.
