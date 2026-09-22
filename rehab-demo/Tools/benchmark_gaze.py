#!/usr/bin/env python3
"""Deterministic ONNX Runtime smoke benchmark for the bundled gaze model."""

from __future__ import annotations

import argparse
import math
import time
from pathlib import Path

import numpy as np
import onnxruntime as ort
from PIL import Image


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("model", type=Path)
    parser.add_argument("eye_image", type=Path)
    parser.add_argument("--iterations", type=int, default=30)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    options = ort.SessionOptions()
    options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    options.intra_op_num_threads = 2
    session = ort.InferenceSession(
        str(args.model),
        sess_options=options,
        providers=["CPUExecutionProvider"],
    )

    image = Image.open(args.eye_image).convert("RGB")
    image = image.resize((60, 36), Image.Resampling.BILINEAR)
    tensor = np.asarray(image, dtype=np.float32).transpose(2, 0, 1)[None] / 255.0

    latencies: list[float] = []
    output: np.ndarray | None = None
    warmup_count = 4
    for index in range(max(1, args.iterations) + warmup_count):
        started_at = time.perf_counter()
        output = session.run(["output"], {"input": tensor})[0]
        elapsed = (time.perf_counter() - started_at) * 1_000
        if index >= warmup_count:
            latencies.append(elapsed)

    assert output is not None
    vector = np.asarray(output).reshape(-1)[:3].astype(float)
    vector /= max(float(np.linalg.norm(vector)), 1.0e-8)
    # MPIIGaze convention, shared with the iPhone analysis implementation.
    pitch = math.degrees(math.asin(float(np.clip(-vector[1], -1, 1))))
    yaw = math.degrees(math.atan2(-vector[0], -vector[2]))
    print(
        "SwinUNetGaze CPU: "
        f"median={np.median(latencies):.1f}ms "
        f"p95={np.percentile(latencies, 95):.1f}ms "
        f"iterations={len(latencies)} "
        f"yaw={yaw:.1f}° pitch={pitch:.1f}° "
        f"output={vector.tolist()}"
    )


if __name__ == "__main__":
    main()
