#!/usr/bin/env python3
"""Build deterministic, lightweight evidence data for the BEFAST slide demo."""

from __future__ import annotations

import csv
import json
import math
import os
from pathlib import Path
import wave

import cv2
import numpy as np
import torch
import torchaudio


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "composition" / "assets"


def rounded(value: float, digits: int = 4) -> float:
    return round(float(value), digits)


def aeye_motion() -> dict:
    source = ASSETS / "nystagmus-demo.mp4"
    capture = cv2.VideoCapture(str(source))
    fps = capture.get(cv2.CAP_PROP_FPS) or 30.0
    beta = 0.25
    memory = None
    energies: list[dict] = []
    peak = (-1.0, None, None, 0)
    frame_index = 0

    while True:
        ok, frame = capture.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        small = cv2.resize(gray, (80, 60), interpolation=cv2.INTER_AREA).astype(np.float32) / 255.0
        if memory is None:
            memory = small.copy()
        filtered = np.abs(small - memory)
        memory = (1.0 - beta) * memory + beta * small
        energy = float(filtered.mean())
        if frame_index % max(1, round(fps / 30.0)) == 0:
            energies.append({"t": rounded(frame_index / fps, 3), "v": rounded(energy, 5)})
        if energy > peak[0]:
            peak = (energy, gray.copy(), filtered.copy(), frame_index)
        frame_index += 1

    capture.release()
    raw = peak[1]
    filtered = peak[2]
    assert raw is not None and filtered is not None
    cv2.imwrite(str(ASSETS / "aeye-peak-frame.png"), raw)
    heat = np.clip(filtered / max(float(filtered.max()), 1e-6) * 255.0, 0, 255).astype(np.uint8)
    heat = cv2.applyColorMap(heat, cv2.COLORMAP_INFERNO)
    cv2.imwrite(str(ASSETS / "aeye-recursive-filter.png"), heat)
    return {
        "sourceFps": rounded(fps, 2),
        "beta": beta,
        "frames": frame_index,
        "peakFrame": peak[3],
        "peakTime": rounded(peak[3] / fps, 3),
        "energy": energies,
    }


def speech_features() -> dict:
    source = ASSETS / "speech-sample.wav"
    with wave.open(str(source), "rb") as stream:
        rate = stream.getframerate()
        channels = stream.getnchannels()
        width = stream.getsampwidth()
        samples = stream.readframes(stream.getnframes())
    if rate != 16000 or channels != 1 or width != 2:
        raise RuntimeError("speech sample must be mono PCM16 at 16 kHz")

    waveform = torch.frombuffer(bytearray(samples), dtype=torch.int16).float().div_(32768.0)
    model = torchaudio.pipelines.WAV2VEC2_BASE.get_model().eval()
    with torch.inference_mode():
        layers, _ = model.extract_features(waveform.unsqueeze(0))

    grouped_layers = []
    activity = []
    for index, layer in enumerate(layers):
        pooled = layer.mean(dim=1).squeeze(0).abs()
        bins = pooled.reshape(24, 32).mean(dim=1)
        grouped_layers.append([rounded(value, 5) for value in bins.tolist()])
        activity.append(
            {
                "layer": index + 1,
                "meanAbs": rounded(layer.abs().mean()),
                "std": rounded(layer.std()),
            }
        )

    waveform_bins = 220
    samples_per_bin = max(1, waveform.numel() // waveform_bins)
    wave_view = waveform[: samples_per_bin * waveform_bins].reshape(waveform_bins, samples_per_bin)
    wave_rms = torch.sqrt(torch.mean(wave_view.square(), dim=1))

    window = torch.hann_window(400)
    spectrum = torch.stft(
        waveform,
        n_fft=512,
        hop_length=160,
        win_length=400,
        window=window,
        return_complex=True,
    ).abs()
    spectrum = torch.log1p(spectrum)
    spectrum = torch.nn.functional.interpolate(
        spectrum.unsqueeze(0).unsqueeze(0), size=(32, 48), mode="bilinear", align_corners=False
    ).squeeze()
    spectrum = (spectrum - spectrum.min()) / max(float(spectrum.max() - spectrum.min()), 1e-6)

    return {
        "sampleRate": rate,
        "duration": rounded(waveform.numel() / rate, 3),
        "model": "torchaudio WAV2VEC2_BASE / fairseq base LS-960",
        "embeddingShape": [int(layers[0].shape[1]), int(layers[0].shape[2])],
        "waveformRms": [rounded(value, 5) for value in wave_rms.tolist()],
        "spectrogram": [[rounded(value, 4) for value in row] for row in spectrum.tolist()],
        "layerActivity": activity,
        "layerHeatmap": grouped_layers,
    }


def upper_limb() -> dict:
    repetitions_path = ASSETS / "data" / "upper-limb-repetitions.csv"
    thresholds_path = ASSETS / "data" / "upper-limb-thresholds.csv"
    with repetitions_path.open(newline="", encoding="utf-8") as stream:
        rows = list(csv.DictReader(stream))
    with thresholds_path.open(newline="", encoding="utf-8") as stream:
        thresholds = {row["metric"]: row for row in csv.DictReader(stream)}

    detection = [row for row in rows if row["cohort"] == "detection"]
    elbow_rows = [row for row in detection if row["condition"] in {"COR", "ELB"}]
    points = [
        {
            "condition": row["condition"],
            "value": rounded(float(row["elbow_min_deg"]), 2),
            "flag": int(row["pred_elbow"]),
        }
        for row in elbow_rows
    ]
    sampled = points[:: max(1, math.ceil(len(points) / 140))][:140]
    by_condition = {}
    for condition in ("COR", "ELB"):
        values = np.array([point["value"] for point in points if point["condition"] == condition])
        by_condition[condition] = {
            "n": int(values.size),
            "median": rounded(np.median(values), 2),
            "q1": rounded(np.quantile(values, 0.25), 2),
            "q3": rounded(np.quantile(values, 0.75), 2),
        }
    return {
        "rows": len(rows),
        "detectionRows": len(detection),
        "elbowThresholdDeg": rounded(float(thresholds["elbow"]["threshold"]), 1),
        "violationWindowMs": int(float(thresholds["violation_window"]["threshold"])),
        "points": sampled,
        "summary": by_condition,
    }


def synthetic_face() -> dict:
    symmetric = [0.74, 0.62, 0.53, 0.46, 0.39, 0.34, 0.29, 0.25, 0.21]
    weak_side = [0.46, 0.41, 0.38, 0.34, 0.29, 0.25, 0.22, 0.19, 0.16]
    return {
        "note": "procedural non-clinical illustration",
        "leftHog": symmetric,
        "rightHog": weak_side,
        "hogDistance": rounded(np.linalg.norm(np.array(symmetric) - np.array(weak_side)), 3),
        "landmarks": {
            "leftMouth": [0.36, 0.70],
            "rightMouth": [0.68, 0.75],
            "nose": [0.52, 0.52],
            "leftEye": [0.40, 0.39],
            "rightEye": [0.64, 0.40],
        },
    }


def main() -> None:
    payload = {
        "schema": "befast.feature.demo.v1",
        "provenance": {
            "aeye": "recursive filtered-image method reproduced from Wagle et al. 2022 on a CC BY-SA eye clip",
            "upperLimb": "Pavlikov et al. open repetition table, CC BY 4.0",
            "speech": "actual wav2vec2-base-960h embeddings on a synthetic non-patient voice sample",
            "face": "procedural illustration of the HOG/asymmetry feature concept; not patient data",
        },
        "aeye": aeye_motion(),
        "upperLimb": upper_limb(),
        "speech": speech_features(),
        "face": synthetic_face(),
    }
    output = ASSETS / "research-data.js"
    output.write_text(
        "window.BEFAST_RESEARCH_DATA = " + json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + ";\n",
        encoding="utf-8",
    )
    print(output)


if __name__ == "__main__":
    main()
