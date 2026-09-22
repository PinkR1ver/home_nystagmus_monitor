# BEFAST feature extraction demo — sources and reproducibility

Checked on 2026-09-05. This deck separates the paper's method from the exact
software or weights available for reuse. “Method reproduction” never means the
original trained model was obtained.

| Module | Paper method | Reusable artifact found | Demo status |
|---|---|---|---|
| Face | Zhuang et al. align face geometry and intensity, extract HOG/appearance features, then classify laterality; Aldridge et al. aggregate frame predictions by voting | No public paper weights or training set located; authors state data are available on request | Licensed Aldridge Figure 1 plus a local HOG/asymmetry method illustration |
| Eye — aEYE | Recursive filtered images (`beta=0.25`) followed by ImageNet ResNet/VGG classifiers and video-level hard/soft voting | Paper and formula are open; AVERT clips and trained weights were not released | Exact recursive filter reproduced on a CC BY-SA nystagmus clip; classifier output is shown only as the paper's reported result |
| Eye — EyePhone | MediaPipe facial/iris landmarks, iris-minus-nose translation correction, cover detection from eye-region luminance, calibrated vertical displacement | MediaPipe model/API are public; EyePhone app source and study recordings are not public downloads | Licensed paper trace explains the feature; geometry pipeline is described without a diagnostic result |
| Arm | MediaPipe pose coordinates transformed into elbow, asymmetry, shoulder, trunk and head metrics with a 250 ms persistence gate | Analysis code MIT; 913 repetition records CC BY 4.0; per-frame keypoints available by request | Real released repetition table drives the elbow threshold plot |
| Balance | 3D skeleton coordinates → Skeleton-Attention-LSTM-Inception classifier | No public code, weights or patient gait data located | Existing YOLO pose trace demonstrates the interpretable kinematic layer; classifier is a labeled proxy |
| Speech | `wav2vec2-base-960h` layer embeddings, temporal mean to 768 dimensions, RBF-SVM for detection/severity | Base wav2vec2 weights are public under Apache-2.0; UA-Speech requires an academic/government request and forbids redistribution | Actual wav2vec2 base embeddings extracted from a synthetic non-patient utterance |

## Primary papers and model/data sources

- Zhuang Y et al. *Facial Weakness Analysis and Quantification of Static Images* (2020): https://doi.org/10.1109/JBHI.2020.2964520
- Aldridge CM et al. *Human vs. Machine Learning Based Detection of Facial Weakness Using Video Analysis* (2022): https://doi.org/10.3389/fneur.2022.878282
- Wagle N et al. *aEYE: A deep learning system for video nystagmus detection* (2022): https://doi.org/10.3389/fneur.2022.963968
- Babaria R et al. *Detecting simulated skew deviation using a smartphone eye-tracking application (EyePhone)* (2026): https://doi.org/10.3389/fneur.2026.1860824
- Friedrich MU et al. *Smartphone video nystagmography using convolutional neural networks: ConVNG* (2023), an open-weight alternative cited by EyePhone: https://doi.org/10.1007/s00415-022-11493-1
- ConVNG model archive: https://doi.org/10.7910/DVN/GTUMAJ
- Pavlikov A et al. *Markerless On-Device Detection of Compensatory Movement Patterns in Upper-Limb Rehabilitation from Monocular RGB Video* (2026): https://doi.org/10.3390/s26165054
- Pavlikov code/data: https://github.com/mel0d1an/upper-limb-compensation-validation and https://doi.org/10.5281/zenodo.21747009
- Peng Y et al. *Smartphone-Based Brunnstrom Stage Classification of Hemiparetic Gait* (2026): https://doi.org/10.1109/TBME.2026.3713910
- Javanmardi F et al. *Wav2vec-based Detection and Severity Level Classification of Dysarthria from Speech* (2023): https://arxiv.org/abs/2309.14107
- Meta wav2vec2 base model: https://huggingface.co/facebook/wav2vec2-base-960h
- UA-Speech access and license restrictions: https://speechtechnology.web.illinois.edu/uaspeech/
- MediaPipe Face Landmarker: https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker

## Demo media

- Paper figures: Aldridge et al. Figure 1, Wagle et al. Figure 4, and Babaria et al. Figure 2 are reused from their Frontiers articles under CC BY 4.0.
- Arm figure: Pavlikov et al. Figure 4 is regenerated from the repository's released repetition table; repository code is MIT and data are CC BY 4.0.
- Eye clip: “Nystagmus eye movement” by Mr.Polaz, CC BY-SA 4.0: https://commons.wikimedia.org/wiki/File:Nystagmus_eye_movement.gif
- Body video: VisionMD-Gait demo with locally generated YOLO11n pose overlay: https://github.com/mea-lab/GaitValidation/blob/main/DEMO/demo.mp4. The source repository does not state a clear root media license; replace it before public/commercial redistribution.
- Speech: locally synthesized non-patient voice, 16 kHz mono PCM. It is used only to demonstrate feature extraction and carries no dysarthria label.

## Rebuild

The generated `composition/assets/research-data.js` contains the recursive-filter
motion energy, open upper-limb summary, speech waveform/spectrogram and actual
wav2vec2 embeddings. Rebuild it with the project script after providing compatible
Python packages (`opencv-python`, `numpy`, `torch`, `torchaudio`).
