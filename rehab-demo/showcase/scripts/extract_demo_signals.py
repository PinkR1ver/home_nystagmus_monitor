#!/usr/bin/env python3
"""Extract reproducible demo signals from the exact showcase videos.

Body landmarks come from the third-party YOLO11n Pose weights. Eye motion is
measured as the pupil-centroid displacement in the adopted close-up video.
The generated JavaScript is copied into both HyperFrames projects so the film
and slideshow render from one data contract.
"""

from __future__ import annotations

import argparse
import json
import math
import shutil
import subprocess
from pathlib import Path

import cv2
import numpy as np
from scipy import signal as scipy_signal
from scipy.ndimage import median_filter
from ultralytics import YOLO


COCO_BONES = [
    [0, 1], [0, 2], [1, 3], [2, 4],
    [5, 6], [5, 7], [7, 9], [6, 8], [8, 10],
    [5, 11], [6, 12], [11, 12], [11, 13], [13, 15], [12, 14], [14, 16],
]


def angle(a: np.ndarray, b: np.ndarray, c: np.ndarray) -> float:
    u, v = a - b, c - b
    denom = max(float(np.linalg.norm(u) * np.linalg.norm(v)), 1e-6)
    return math.degrees(math.acos(float(np.clip(np.dot(u, v) / denom, -1, 1))))


def read_sampled_frames(path: Path, sample_fps: float) -> tuple[list[np.ndarray], list[float], float]:
    cap = cv2.VideoCapture(str(path))
    source_fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    stride = max(1, round(source_fps / sample_fps))
    frames, times = [], []
    index = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        if index % stride == 0:
            frames.append(frame)
            times.append(index / source_fps)
        index += 1
    cap.release()
    return frames, times, source_fps / stride


def extract_body(path: Path, weights: Path, sample_fps: float) -> dict:
    frames, times, effective_fps = read_sampled_frames(path, sample_fps)
    model = YOLO(str(weights))
    results = model.predict(frames, imgsz=640, conf=0.25, device="mps", verbose=False, batch=12)
    output = []
    for frame, timestamp, result in zip(frames, times, results):
        height, width = frame.shape[:2]
        if result.keypoints is None or len(result.keypoints.data) == 0:
            continue
        person_index = int(np.argmax(result.boxes.conf.cpu().numpy()))
        points = result.keypoints.data[person_index].cpu().numpy()
        normalized = np.column_stack((points[:, 0] / width, points[:, 1] / height, points[:, 2]))
        left_knee = angle(normalized[11, :2], normalized[13, :2], normalized[15, :2])
        right_knee = angle(normalized[12, :2], normalized[14, :2], normalized[16, :2])
        hip_center = (normalized[11, :2] + normalized[12, :2]) / 2
        shoulder_center = (normalized[5, :2] + normalized[6, :2]) / 2
        trunk = shoulder_center - hip_center
        trunk_tilt = math.degrees(math.atan2(float(trunk[0]), float(-trunk[1])))
        output.append({
            "t": round(timestamp, 3),
            "keypoints": [[round(float(v), 5) for v in row] for row in normalized],
            "visible": int(np.count_nonzero(normalized[:, 2] >= 0.25)),
            "confidence": round(float(np.mean(normalized[:, 2])), 4),
            "leftKneeDeg": round(left_knee, 1),
            "rightKneeDeg": round(right_knee, 1),
            "trunkTiltDeg": round(trunk_tilt, 1),
            "hipCenterY": round(float(hip_center[1]), 5),
            "ankleSeparation": round(float(abs(normalized[15, 0] - normalized[16, 0])), 5),
            "shoulderCenterX": round(float(shoulder_center[0]), 5),
        })
    if not output:
        raise RuntimeError(f"YOLO11n Pose found no person in {path}")
    ankle_separation = [f["ankleSeparation"] for f in output]
    shoulder_x = [f["shoulderCenterX"] for f in output]
    return {
        "sampleFps": round(effective_fps, 3),
        "duration": round(times[-1] if times else 0, 3),
        "bones": COCO_BONES,
        "frames": output,
        "summary": {
            "meanConfidence": round(float(np.mean([f["confidence"] for f in output])), 4),
            "minVisible": min(f["visible"] for f in output),
            "meanVisible": round(float(np.mean([f["visible"] for f in output])), 2),
            "hipCenterYRange": [
                round(min(f["hipCenterY"] for f in output), 5),
                round(max(f["hipCenterY"] for f in output), 5),
            ],
            "verticalExcursion": round(
                max(f["hipCenterY"] for f in output) - min(f["hipCenterY"] for f in output), 5
            ),
            "ankleSeparationRange": [round(min(ankle_separation), 5), round(max(ankle_separation), 5)],
            "shoulderSway": round(max(shoulder_x) - min(shoulder_x), 5),
        },
    }


def nearest_frame(frames: list[dict], timestamp: float) -> dict:
    times = np.fromiter((frame["t"] for frame in frames), dtype=float)
    index = int(np.searchsorted(times, timestamp, side="left"))
    if index <= 0:
        return frames[0]
    if index >= len(frames):
        return frames[-1]
    return frames[index - 1] if timestamp - times[index - 1] <= times[index] - timestamp else frames[index]


def render_body_overlay(source: Path, body: dict, output: Path, output_height: int = 1080) -> None:
    """Burn the exact YOLO keypoints into the walking video.

    The overlay is rendered from the same normalized points exported to the UI,
    so the film, slideshow, and source footage stay frame-aligned.
    """
    cap = cv2.VideoCapture(str(source))
    source_fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    source_width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    source_height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    output_width = int(round(source_width * output_height / source_height / 2) * 2)
    output.parent.mkdir(parents=True, exist_ok=True)
    command = [
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
        "-f", "rawvideo", "-pix_fmt", "bgr24", "-s", f"{output_width}x{output_height}",
        "-r", f"{source_fps:.6f}", "-i", "-", "-an",
        "-c:v", "libx264", "-preset", "medium", "-crf", "19",
        "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(output),
    ]
    encoder = subprocess.Popen(command, stdin=subprocess.PIPE)
    frame_index = 0
    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            timestamp = frame_index / source_fps
            frame_index += 1
            frame = cv2.resize(frame, (output_width, output_height), interpolation=cv2.INTER_AREA)
            pose = nearest_frame(body["frames"], timestamp)
            points = pose["keypoints"]
            for a, b in COCO_BONES:
                if points[a][2] < 0.25 or points[b][2] < 0.25:
                    continue
                pa = (int(points[a][0] * output_width), int(points[a][1] * output_height))
                pb = (int(points[b][0] * output_width), int(points[b][1] * output_height))
                cv2.line(frame, pa, pb, (255, 194, 72), 7, cv2.LINE_AA)
                cv2.line(frame, pa, pb, (255, 247, 220), 2, cv2.LINE_AA)
            for x, y, confidence in points:
                if confidence < 0.25:
                    continue
                center = (int(x * output_width), int(y * output_height))
                cv2.circle(frame, center, 9, (25, 25, 25), -1, cv2.LINE_AA)
                cv2.circle(frame, center, 6, (64, 226, 255), -1, cv2.LINE_AA)
            cv2.rectangle(frame, (22, 22), (min(output_width - 22, 470), 116), (15, 20, 26), -1)
            cv2.putText(frame, "YOLO11n POSE  |  WALK", (42, 60), cv2.FONT_HERSHEY_SIMPLEX,
                        0.72, (255, 255, 255), 2, cv2.LINE_AA)
            cv2.putText(frame, f"{pose['visible']:02d}/17 joints   conf {pose['confidence']:.3f}   {timestamp:04.1f}s",
                        (42, 94), cv2.FONT_HERSHEY_SIMPLEX, 0.53, (92, 220, 255), 1, cv2.LINE_AA)
            assert encoder.stdin is not None
            encoder.stdin.write(frame.tobytes())
    finally:
        cap.release()
        if encoder.stdin:
            encoder.stdin.close()
        return_code = encoder.wait()
    if return_code != 0:
        raise RuntimeError(f"ffmpeg failed while rendering {output} (exit {return_code})")


def pupil_candidate(frame: np.ndarray, previous: tuple[float, float] | None) -> tuple[float, float, float]:
    height, width = frame.shape[:2]
    x0, x1 = int(width * 0.05), int(width * 0.95)
    y0, y1 = int(height * 0.12), int(height * 0.80)
    roi = frame[y0:y1, x0:x1]
    gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
    gray = cv2.GaussianBlur(gray, (7, 7), 2)
    circles = cv2.HoughCircles(
        gray, cv2.HOUGH_GRADIENT, dp=1.2, minDist=100,
        param1=60, param2=18, minRadius=50, maxRadius=170,
    )
    candidates = [] if circles is None else circles[0]
    plausible = []
    for cx, cy, radius in candidates:
        absolute = (float(cx + x0), float(cy + y0))
        if not height * 0.27 <= absolute[1] <= height * 0.64:
            continue
        distance = 0.0 if previous is None else math.hypot(absolute[0] - previous[0], absolute[1] - previous[1])
        if previous is not None and distance > 120:
            continue
        plausible.append((float(radius) - distance * 0.20, absolute[0], absolute[1], float(radius)))
    if not plausible:
        if previous is None:
            return width / 2, height / 2, 0.0
        return previous[0], previous[1], 0.0
    best = max(plausible, key=lambda item: item[0])
    return best[1], best[2], min(1.0, best[3] / 170.0)


def safe_filtfilt(data: np.ndarray, cutoff: float, fs: float, btype: str, order: int = 5) -> np.ndarray:
    nyquist = 0.5 * fs
    normalized = cutoff / nyquist
    if normalized >= 1 or len(data) < 4:
        return data.copy()
    b, a = scipy_signal.butter(order, normalized, btype=btype, analog=False)
    padlen = min(len(data) - 1, 3 * (max(len(b), len(a)) - 1))
    return scipy_signal.filtfilt(b, a, data, padlen=padlen)


def has_consecutive_patterns(patterns: list[dict], positive: bool, minimum: int = 3,
                             max_gap: float = 0.1) -> bool:
    chosen = [p for p in patterns if (p["slowSlope"] > 0) == positive]
    if len(chosen) < minimum:
        return False
    chosen.sort(key=lambda p: p["timePoint"])
    consecutive = best = 1
    for previous, current in zip(chosen, chosen[1:]):
        previous_end = previous["timePoint"] + previous["totalTime"] / 2
        current_start = current["timePoint"] - current["totalTime"] / 2
        consecutive = consecutive + 1 if current_start - previous_end <= max_gap else 1
        best = max(best, consecutive)
    return best >= minimum


def analyze_nystagmus(times: np.ndarray, displacement: np.ndarray, sample_fps: float) -> dict:
    """Port the VertiWisdom phase logic to normalized video displacement.

    The reference thresholds are expressed in gaze degrees. This demo has only
    image-plane pupil displacement, so filtering and temporal/ratio criteria are
    preserved while amplitude thresholds are explicitly expressed as % frame width.
    """
    values_pct = displacement * 100.0
    highpass = safe_filtfilt(values_pct, 0.1, sample_fps, "highpass", order=5)
    lowpass_cutoff = min(6.0, sample_fps * 0.5 * 0.90)
    lowpass = safe_filtfilt(highpass, lowpass_cutoff, sample_fps, "lowpass", order=5)
    duration = float(times[-1] - times[0]) if len(times) > 1 else 0.0
    target_samples = max(len(lowpass), int(duration * 600.0))
    filtered = scipy_signal.resample(lowpass, target_samples) if target_samples else np.array([])
    processed_time = np.linspace(times[0], times[-1], len(filtered)) if len(filtered) else np.array([])

    peak_to_peak = float(np.ptp(filtered)) if len(filtered) else 0.0
    prominence = max(0.2, peak_to_peak * 0.03)
    min_amplitude = max(0.5, peak_to_peak * 0.15)
    distance = max(1, int(0.25 * 600.0))
    peaks, _ = scipy_signal.find_peaks(filtered, prominence=prominence, distance=distance)
    valleys, _ = scipy_signal.find_peaks(-filtered, prominence=prominence, distance=distance)
    turning = np.sort(np.concatenate([peaks, valleys]))
    patterns: list[dict] = []
    for index in range(1, len(turning) - 1):
        i1, i2, i3 = (int(turning[index - 1]), int(turning[index]), int(turning[index + 1]))
        t1, t2, t3 = processed_time[[i1, i2, i3]]
        y1, y2, y3 = filtered[[i1, i2, i3]]
        if not (y2 > y1 and y2 > y3):
            continue
        amplitude_left, amplitude_right = abs(y2 - y1), abs(y2 - y3)
        amplitude = max(amplitude_left, amplitude_right)
        total_time = t3 - t1
        if amplitude < min_amplitude or not 0.15 <= total_time <= 1.5:
            continue
        slope_before = (y2 - y1) / max(t2 - t1, 1e-9)
        slope_after = (y3 - y2) / max(t3 - t2, 1e-9)
        if abs(slope_before) > abs(slope_after):
            fast_slope, slow_slope, fast_first = slope_before, slope_after, True
        else:
            fast_slope, slow_slope, fast_first = slope_after, slope_before, False
        if fast_slope * slow_slope > 0:
            continue
        ratio = abs(fast_slope) / abs(slow_slope) if slow_slope else float("inf")
        if not 1.2 <= ratio <= 10.0:
            continue
        patterns.append({
            "turningIndex": index,
            "turningPointIndices": [i1, i2, i3],
            "timePoint": round(float(t2), 4),
            "peak": round(float(y2), 4),
            "amplitude": round(float(amplitude), 4),
            "slowSlope": round(float(slow_slope), 4),
            "fastSlope": round(float(fast_slope), 4),
            "ratio": round(float(ratio), 3),
            "fastPhaseFirst": fast_first,
            "totalTime": round(float(total_time), 4),
        })

    positive = has_consecutive_patterns(patterns, True)
    negative = has_consecutive_patterns(patterns, False)
    if positive and negative:
        direction, valid = "bidirectional", patterns
    elif positive:
        direction, valid = "left", [p for p in patterns if p["slowSlope"] > 0]
    elif negative:
        direction, valid = "right", [p for p in patterns if p["slowSlope"] < 0]
    else:
        direction, valid = "none", []
    slow_slopes = np.array([abs(p["slowSlope"]) for p in valid], dtype=float)
    spv = float(np.median(slow_slopes)) if len(slow_slopes) else 0.0
    cv = 0.0
    if len(slow_slopes) >= 2 and np.median(slow_slopes):
        median = np.median(slow_slopes)
        cv = float(1.4826 * np.median(np.abs(slow_slopes - median)) / median * 100)

    phases = []
    for pattern_index, pattern in enumerate(patterns):
        i1, i2, i3 = pattern["turningPointIndices"]
        first_type, second_type = ("fast", "slow") if pattern["fastPhaseFirst"] else ("slow", "fast")
        phases.extend([
            {"pattern": pattern_index, "type": first_type, "startT": round(float(processed_time[i1]), 4),
             "endT": round(float(processed_time[i2]), 4), "startY": round(float(filtered[i1]), 4),
             "endY": round(float(filtered[i2]), 4)},
            {"pattern": pattern_index, "type": second_type, "startT": round(float(processed_time[i2]), 4),
             "endT": round(float(processed_time[i3]), 4), "startY": round(float(filtered[i2]), 4),
             "endY": round(float(filtered[i3]), 4)},
        ])
    stride = max(1, round(len(filtered) / 600))
    return {
        "algorithm": "VertiWisdom-style: Butterworth HP 0.1 Hz + LP 6 Hz + 600 Hz resample + turning-point slope ratio",
        "unit": "% frame width",
        "clinicalAngle": False,
        "thresholds": {"prominence": round(prominence, 4), "minAmplitude": round(min_amplitude, 4),
                       "minPatternSec": 0.15, "maxPatternSec": 1.5, "slopeRatio": [1.2, 10.0],
                       "minimumConsecutive": 3},
        "frames": [{"t": round(float(t), 4), "raw": round(float(raw), 4), "highpass": round(float(hp), 4),
                    "lowpass": round(float(lp), 4)} for t, raw, hp, lp in zip(times, values_pct, highpass, lowpass)],
        "processed": [{"t": round(float(processed_time[i]), 4), "y": round(float(filtered[i]), 4)}
                      for i in range(0, len(filtered), stride)],
        "turningPoints": [{"t": round(float(processed_time[i]), 4), "y": round(float(filtered[i]), 4)}
                          for i in turning],
        "patterns": patterns,
        "phases": phases,
        "summary": {"hasNystagmus": bool(positive or negative), "direction": direction,
                    "candidatePatterns": len(patterns), "validPatterns": len(valid),
                    "slowPhaseVelocity": round(spv, 4), "cv": round(cv, 2),
                    "peakToPeak": round(peak_to_peak, 4)},
    }


def extract_eye(path: Path, sample_fps: float) -> dict:
    frames, times, effective_fps = read_sampled_frames(path, sample_fps)
    raw, previous = [], None
    for frame, timestamp in zip(frames, times):
        cx, cy, quality = pupil_candidate(frame, previous)
        if quality > 0:
            previous = (cx, cy)
        raw.append([timestamp, cx / frame.shape[1], cy / frame.shape[0], quality])
    x = np.array([row[1] for row in raw], dtype=float)
    y = np.array([row[2] for row in raw], dtype=float)
    if len(x) >= 3:
        # Reject single-frame Hough jumps without inventing intermediate motion.
        x = median_filter(x, size=3, mode="nearest")
        y = median_filter(y, size=3, mode="nearest")
    x -= np.median(x)
    y -= np.median(y)
    output = [{
        "t": round(row[0], 3),
        "x": round(float(px), 5),
        "y": round(float(py), 5),
        "quality": round(float(row[3]), 3),
    } for row, px, py in zip(raw, x, y)]
    analysis = analyze_nystagmus(np.array(times), x, effective_fps)
    return {
        "sampleFps": round(effective_fps, 3),
        "duration": round(times[-1] if times else 0, 3),
        "frames": output,
        "summary": {
            "horizontalPeakToPeak": round(float(np.ptp(x)), 5),
            "verticalPeakToPeak": round(float(np.ptp(y)), 5),
            "meanQuality": round(float(np.mean([f["quality"] for f in output])), 3),
        },
        "analysis": analysis,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--body-video", type=Path, required=True)
    parser.add_argument("--eye-video", type=Path, required=True)
    parser.add_argument("--weights", type=Path, required=True)
    parser.add_argument("--body-overlay", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--copy-to", type=Path, action="append", default=[])
    args = parser.parse_args()

    body = extract_body(args.body_video, args.weights, 10.0)
    if args.body_overlay:
        render_body_overlay(args.body_video, body, args.body_overlay)
    payload = {
        "schema": "rehab.demo.signals.v2",
        "provenance": {
            "body": "YOLO11n Pose inference on VisionMD-Gait's exact frontal-plane walking demo video",
            "bodySource": "https://github.com/mea-lab/GaitValidation/blob/main/DEMO/demo.mp4",
            "eye": "pupil-centroid displacement measured on the exact adopted direct-eye video",
            "reference": "/Volumes/macOSexternal/Documents/proj/SwinUNet-VOG/vertiwisdom.py",
            "note": "2D source-video measurements; normalized image-plane eye units are not gaze degrees or clinical SPV",
        },
        "body": body,
        "eye": extract_eye(args.eye_video, 30.0),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        "window.REHAB_DEMO_SIGNALS = " + json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + ";\n",
        encoding="utf-8",
    )
    for destination in args.copy_to:
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(args.output, destination)
    print(json.dumps({"body": payload["body"]["summary"], "eye": payload["eye"]["summary"]}, indent=2))


if __name__ == "__main__":
    main()
