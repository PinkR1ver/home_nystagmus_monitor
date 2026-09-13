# Third-party model notice

## YOLO11n Pose

- Purpose: on-device full-body and face-keypoint pose estimation
- Source: `Ultralytics/YOLO11`
- Hugging Face weights: `yolo11n-pose.pt`
- Source revision: `ef78744`
- Source SHA-256: `869e83fcdffdc7371fa4e34cd8e51c838cc729571d1635e5141e3075e9319dc0`
- Bundled artifact: `YOLO11nPose.mlpackage`
- Conversion: Ultralytics `8.3.217`, Core ML Tools `8.3.0`, 640×640, FP16 weights
- License declared by the source repository: AGPL-3.0

This model is included for the rehabilitation demo. Confirm AGPL obligations or obtain
an Ultralytics commercial license before distributing a proprietary production build.

## FCQ Head Pose

- Purpose: independent head yaw / pitch / roll and face-input quality
- Source: `shafi-afridi/face-capture-quality`
- Bundled artifact: `HeadPose.mlpackage`
- Architecture: MobileNetV3-Small, 160×160 RGB input, FP16 Core ML
- Output: yaw, pitch, roll, usable, blur, occluded, bad exposure
- Model SHA-256:
  - spec: `26be539bc8947e71917159c630fe410b10b0cc4983108af740063d7846f4f3ac`
  - weights: `aa846e70404ef4668465e6e9fd654b38fbe88d856c3de04f2c773e030afca7e9`
- License declared by the model card: CC-BY-NC-4.0

The published weights use research / non-commercial datasets. They are suitable for
this internal demo, not a commercial production release.

## SwinUNet Gaze

- Purpose: eye-crop to 3D gaze vector
- Bundled artifact: `swinunet_web.onnx`
- Input / output: `[1, 3, 36, 60]` RGB float → `[1, 3]` gaze vector
- SHA-256: `c5d6c1ec5b683a0221139b5c9dc36216175e232ca3ee9e1a58828949c621de16`
- Runtime: ONNX Runtime iOS `1.24.2`
- Origin: pre-existing project asset shared with the Android and iPhone apps
- License / training-data provenance: not recorded in the repository

Do not distribute the gaze weights outside the demo until their source, training data,
and redistribution terms are documented.
