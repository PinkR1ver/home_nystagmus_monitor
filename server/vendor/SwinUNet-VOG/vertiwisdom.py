"""
VertiWisdom - 眼动视频分析系统
极简版：上传视频 → 自动分析 → 下载PDF医学报告
"""

import os
import sys
import time
import tempfile
import io
from datetime import datetime
from typing import Optional, Tuple, Dict, List, Any

import cv2
import numpy as np
import torch
import streamlit as st
import scipy.signal
import torchvision.transforms as T
import matplotlib.pyplot as plt
import matplotlib
matplotlib.use('Agg')

# 设置matplotlib中文字体 (Windows 11)
plt.rcParams['font.sans-serif'] = ['Microsoft YaHei', 'SimHei', 'DejaVu Sans']
plt.rcParams['axes.unicode_minus'] = False

try:
    from decord import VideoReader, cpu
    DECORD_AVAILABLE = True
except ImportError:
    DECORD_AVAILABLE = False

# PDF generation
from reportlab.lib.pagesizes import A4
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import mm, cm
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, 
    Image as RLImage, PageBreak, HRFlowable
)
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

# 注册中文字体 (Windows 11)
CHINESE_FONT_NAME = 'ChineseFont'
CHINESE_FONT_REGISTERED = False

def register_chinese_font():
    """注册中文字体，优先使用微软雅黑"""
    global CHINESE_FONT_REGISTERED
    if CHINESE_FONT_REGISTERED:
        return True
    
    # Windows 11 常用中文字体路径
    font_paths = [
        r"C:\Windows\Fonts\msyh.ttc",      # 微软雅黑
        r"C:\Windows\Fonts\msyhl.ttc",     # 微软雅黑Light
        r"C:\Windows\Fonts\simhei.ttf",    # 黑体
        r"C:\Windows\Fonts\simsun.ttc",    # 宋体
        r"C:\Windows\Fonts\simkai.ttf",    # 楷体
    ]
    
    for font_path in font_paths:
        if os.path.exists(font_path):
            try:
                pdfmetrics.registerFont(TTFont(CHINESE_FONT_NAME, font_path))
                CHINESE_FONT_REGISTERED = True
                return True
            except Exception:
                continue
    
    return False

# Add current directory to path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from preprocessing import EyeImagePreprocessor
from model import GazeSwinUNet, TIMM_AVAILABLE
from nystagmus import NystagmusDetector, NystagmusAnalyzer, InflectionPointDetector


# ==============================================================================
#  工具函数
# ==============================================================================
def vector_to_pitch_yaw(vector: np.ndarray) -> np.ndarray:
    """
    Convert 3D gaze vector(s) to pitch/yaw in degrees.
    MPIIGaze convention:
      gaze = (x, y, z)
      pitch = arcsin(-y)
      yaw   = arctan2(-x, -z)
    """
    vec = np.atleast_2d(vector)
    x, y, z = vec[:, 0], vec[:, 1], vec[:, 2]
    pitch = np.arcsin(np.clip(-y, -1.0, 1.0))
    yaw = np.arctan2(-x, -z)
    angles = np.stack([pitch, yaw], axis=1)
    return np.degrees(angles)


# ==============================================================================
#  信号处理
# ==============================================================================
class SignalProcessor:
    """信号预处理：中值滤波 + 低通滤波"""

    def __init__(self, fps: float = 30.0, low_pass_cutoff: float = 8.0):
        self.fps = fps
        self.nyquist = fps / 2.0
        self.low_pass_cutoff = low_pass_cutoff

    def process(self, data: np.ndarray) -> np.ndarray:
        if len(data) < 15:
            return data

        n_samples, n_features = data.shape
        filled = data.copy()

        # 线性插值填充NaN
        for i in range(n_features):
            y = filled[:, i]
            nans = np.isnan(y)
            if np.all(nans):
                filled[:, i] = 0
                continue
            x = np.arange(n_samples)
            filled[nans, i] = np.interp(x[nans], x[~nans], y[~nans])

        # 中值滤波
        filtered = np.zeros_like(filled)
        kernel_size = 5
        for i in range(n_features):
            filtered[:, i] = scipy.signal.medfilt(filled[:, i], kernel_size=kernel_size)

        # 低通Butterworth滤波
        cutoff = min(self.low_pass_cutoff, self.nyquist - 0.1)
        b, a = scipy.signal.butter(2, cutoff / self.nyquist, btype="low")
        for i in range(n_features):
            filtered[:, i] = scipy.signal.filtfilt(b, a, filtered[:, i])
        return filtered


# ==============================================================================
#  眼部ROI提取
# ==============================================================================
class SingleEyeNormalizer:
    """单眼视频 ROI 提取器。"""

    def __init__(
        self,
        eye: str = "left",
        target_size: Tuple[int, int] = (36, 60),
        padding: float = 0.0,
        enhance_gamma: float = 1.0,
        enhance_clahe_clip: float = 1.2,
    ):
        self.eye = eye.lower()
        self.target_size = target_size
        self.padding = max(0.0, min(float(padding), 0.25))
        self.enhance_gamma = enhance_gamma
        self.clahe = cv2.createCLAHE(clipLimit=enhance_clahe_clip, tileGridSize=(4, 4))
        self.prev_center: Optional[Tuple[float, float]] = None
        self.prev_bounds: Optional[Tuple[float, float]] = None

        # 与训练时保持一致：只做基础增强与尺寸归一化。
        self.preprocessor = EyeImagePreprocessor(
            target_size=target_size,
            normalize_illumination=False,
            normalize_contrast=False,
            normalize_color=False,
            gamma_correction=False,
            adaptive_hist_eq=False,
            use_geometric_normalization=False,
        )

    def _estimate_geometry(self, frame_bgr: np.ndarray) -> Tuple[float, float, float, float]:
        h, w = frame_bgr.shape[:2]
        gray = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2GRAY)
        gray = cv2.GaussianBlur(gray, (9, 9), 0)

        search_x0 = int(w * 0.08)
        search_x1 = max(search_x0 + 1, int(w * 0.92))
        search_y0 = int(h * 0.10)
        search_y1 = max(search_y0 + 1, int(h * 0.90))
        roi = gray[search_y0:search_y1, search_x0:search_x1]

        threshold = float(np.percentile(roi, 12))
        dark_mask = (roi <= threshold).astype(np.uint8)
        kernel = np.ones((5, 5), dtype=np.uint8)
        dark_mask = cv2.morphologyEx(dark_mask, cv2.MORPH_OPEN, kernel)
        dark_mask = cv2.morphologyEx(dark_mask, cv2.MORPH_CLOSE, kernel)

        ys, xs = np.where(dark_mask > 0)
        if len(xs) == 0:
            center_x = w * 0.5
            center_y = h * 0.38
            radius = max(12.0, min(w, h) * 0.08)
        else:
            darkness = np.maximum(threshold - roi[ys, xs], 1.0).astype(np.float32)
            center_x = search_x0 + float(np.average(xs, weights=darkness))
            center_y = search_y0 + float(np.average(ys, weights=darkness))
            area = max(float(len(xs)), 16.0)
            radius = float(np.sqrt(area / np.pi))
            radius = max(12.0, min(radius * 1.35, min(w, h) * 0.18))

        strip_half_width = max(16, int(radius * 2.5))
        x0 = max(0, int(center_x) - strip_half_width)
        x1 = min(w, int(center_x) + strip_half_width)
        strip = gray[:, x0:x1]
        profile = strip.mean(axis=1).astype(np.float32)
        profile = cv2.GaussianBlur(profile.reshape(-1, 1), (1, 31), 0).reshape(-1)
        grad = np.gradient(profile)

        upper_search_start = max(0, int(center_y - radius * 3.0))
        upper_search_end = max(upper_search_start + 1, int(center_y - radius * 0.4))
        lower_search_start = min(h - 1, int(center_y + radius * 0.4))
        lower_search_end = min(h, int(center_y + radius * 3.2))

        if upper_search_end > upper_search_start:
            upper_y = float(upper_search_start + int(np.argmin(grad[upper_search_start:upper_search_end])))
        else:
            upper_y = center_y - radius * 1.6

        if lower_search_end > lower_search_start:
            lower_y = float(lower_search_start + int(np.argmax(grad[lower_search_start:lower_search_end])))
        else:
            lower_y = center_y + radius * 1.6

        if lower_y <= upper_y:
            upper_y = center_y - radius * 1.6
            lower_y = center_y + radius * 1.6

        if self.prev_center is not None:
            alpha = 0.65
            center_x = alpha * self.prev_center[0] + (1.0 - alpha) * center_x
            center_y = alpha * self.prev_center[1] + (1.0 - alpha) * center_y
        if self.prev_bounds is not None:
            alpha = 0.65
            upper_y = alpha * self.prev_bounds[0] + (1.0 - alpha) * upper_y
            lower_y = alpha * self.prev_bounds[1] + (1.0 - alpha) * lower_y

        self.prev_center = (center_x, center_y)
        self.prev_bounds = (upper_y, lower_y)
        return center_x, center_y, upper_y, lower_y

    def _crop_single_eye(self, frame_bgr: np.ndarray) -> Optional[np.ndarray]:
        if frame_bgr is None or frame_bgr.size == 0:
            return None

        h, w = frame_bgr.shape[:2]
        if h < 4 or w < 4:
            return None

        center_x, _, upper_y, lower_y = self._estimate_geometry(frame_bgr)
        target_h, target_w = self.target_size
        target_ratio = float(target_w) / float(target_h)
        current_ratio = float(w) / float(h)

        if current_ratio > target_ratio:
            crop_h = h
            crop_w = max(1, int(round(crop_h * target_ratio)))
        else:
            crop_w = w
            crop_h = max(1, int(round(crop_w / target_ratio)))

        if self.padding > 0:
            crop_w = max(1, int(round(crop_w * (1.0 - self.padding))))
            crop_h = max(1, int(round(crop_h * (1.0 - self.padding))))

        eye_center_y = (upper_y + lower_y) / 2.0
        eyelid_height = max(1.0, lower_y - upper_y)
        desired_center_y = eye_center_y + eyelid_height * 0.03

        x0 = int(round(center_x - crop_w / 2.0))
        y0 = int(round(desired_center_y - crop_h / 2.0))
        x0 = max(0, min(x0, w - crop_w))
        y0 = max(0, min(y0, h - crop_h))
        x1 = min(w, x0 + crop_w)
        y1 = min(h, y0 + crop_h)
        cropped = frame_bgr[y0:y1, x0:x1]
        return cropped if cropped.size > 0 else None

    def _enhance_single_eye(self, frame_bgr: np.ndarray) -> np.ndarray:
        gray = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2GRAY)
        if self.enhance_gamma != 1.0:
            inv_gamma = 1.0 / self.enhance_gamma
            table = np.array([((i / 255.0) ** inv_gamma) * 255 for i in range(256)]).astype("uint8")
            gray = cv2.LUT(gray, table)
        gray = self.clahe.apply(gray)
        p2, p98 = np.percentile(gray, (1, 99))
        if p98 > p2:
            gray = np.clip(gray, p2, p98)
            gray = ((gray - p2) / (p98 - p2) * 255).astype(np.uint8)
        return cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR)

    def extract(self, frame_bgr: np.ndarray) -> Tuple[Optional[torch.Tensor], float]:
        if frame_bgr is None or frame_bgr.size == 0:
            return None, 0.0

        cropped = self._crop_single_eye(frame_bgr)
        if cropped is None:
            return None, 0.0

        roi_tensor = self.preprocessor(self._enhance_single_eye(cropped))
        return roi_tensor, 1.0

    def close(self):
        return None


# 兼容旧入口名称，避免上层调用方立刻断裂。
MediaPipeEyeNormalizer = SingleEyeNormalizer


# ==============================================================================
#  模型加载
# ==============================================================================
@st.cache_resource
def load_gaze_model(ckpt_path: str, device: torch.device):
    checkpoint = torch.load(ckpt_path, map_location=device, weights_only=False)
    model = GazeSwinUNet(
        img_size=(36, 60),
        in_chans=3,
        embed_dim=96,
        depths=[2, 2, 2],
        num_heads=[3, 6, 12],
        window_size=7,
        drop_rate=0.1,
    )
    model.load_state_dict(checkpoint["model_state_dict"])
    model.to(device)
    model.eval()
    return model


# ==============================================================================
#  视频处理 - 批量优化版
# ==============================================================================
def process_video(
    video_path: str,
    gaze_model: torch.nn.Module,
    device: torch.device,
    batch_size: int = 32,
    blink_threshold: float = 0.20,
    blink_extend_frames: int = 9,
    progress_callback=None,
) -> Dict[str, Any]:
    """
    处理视频并返回分析结果
    
    内存优化策略 (极度节省内存):
    1. 强制使用 OpenCV 逐帧读取 (避免 decord 预加载)
    2. 使用 memmap 直接写入磁盘
    3. 所有中间结果立即写磁盘
    4. 避免大数组复制
    """
    import shutil
    import gc
    
    # 创建临时缓存目录
    cache_dir = tempfile.mkdtemp(prefix="vertiwisdom_cache_")
    roi_dir = os.path.join(cache_dir, "roi")
    os.makedirs(roi_dir, exist_ok=True)
    
    # ========== 阶段1: 逐帧提取ROI，全部写入磁盘 ==========
    # 强制使用 OpenCV (decord 会预加载整个视频到内存!)
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError("无法打开视频文件")
    fps = cap.get(cv2.CAP_PROP_FPS)
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    
    if fps <= 0:
        fps = 30.0

    eye_norm = SingleEyeNormalizer(
        eye="left",
        enhance_gamma=1.0,
        enhance_clahe_clip=1.2,
    )

    start_time = time.time()
    
    # 使用 memmap 直接写磁盘 (避免内存中积累)
    ear_path = os.path.join(cache_dir, "ears.npy")
    valid_path = os.path.join(cache_dir, "valid.npy")
    
    # 预分配 memmap
    ear_mmap = np.memmap(ear_path, dtype=np.float32, mode='w+', shape=(total_frames,))
    valid_mmap = np.memmap(valid_path, dtype=bool, mode='w+', shape=(total_frames,))
    
    total_extracted = 0
    
    # 使用帧预读取队列加速 (利用额外4GB内存)
    from queue import Queue
    from threading import Thread
    
    PREFETCH_SIZE = 120  # 预读取120帧 (约100MB内存)
    frame_queue = Queue(maxsize=PREFETCH_SIZE)
    read_done = [False]  # 使用列表以便在闭包中修改
    
    def frame_reader():
        """后台线程读取帧"""
        idx = 0
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            frame_queue.put((idx, frame))
            idx += 1
        read_done[0] = True
    
    # 启动帧读取线程
    reader_thread = Thread(target=frame_reader, daemon=True)
    reader_thread.start()
    
    frame_idx = 0
    while True:
        # 从队列获取帧
        if frame_queue.empty() and read_done[0]:
            break
        
        try:
            idx, frame = frame_queue.get(timeout=1.0)
        except:
            if read_done[0]:
                break
            continue
        
        roi_tensor, ear = eye_norm.extract(frame)
        del frame
        
        ear_mmap[idx] = ear
        
        if roi_tensor is not None:
            roi_file = os.path.join(roi_dir, f"{idx}.pt")
            torch.save(roi_tensor, roi_file)
            valid_mmap[idx] = True
            del roi_tensor
        else:
            valid_mmap[idx] = False
        
        frame_idx = idx + 1
        total_extracted = frame_idx
        
        # 定期刷新
        if frame_idx % 100 == 0:
            ear_mmap.flush()
            valid_mmap.flush()
        
        if progress_callback and total_frames > 0 and frame_idx % 30 == 0:
            progress_callback(min(frame_idx / total_frames * 0.3, 0.3))
    
    reader_thread.join(timeout=2.0)
    cap.release()
    eye_norm.close()
    
    # 最终刷新并释放 memmap
    ear_mmap.flush()
    valid_mmap.flush()
    del ear_mmap, valid_mmap
    gc.collect()
    
    if progress_callback:
        progress_callback(0.32)
    
    # ========== 阶段2: 检测眨眼 (使用 memmap 只读) ==========
    ear_mmap = np.memmap(ear_path, dtype=np.float32, mode='r', shape=(total_extracted,))
    blink_mask = np.array(ear_mmap < blink_threshold)  # 小数组，可以在内存
    del ear_mmap
    
    # 扩展眨眼窗口
    extended_blink = blink_mask.copy()
    for i in range(len(blink_mask)):
        if blink_mask[i]:
            start = max(0, i - blink_extend_frames)
            end = min(len(blink_mask), i + blink_extend_frames + 1)
            extended_blink[start:end] = True
    del blink_mask
    
    # 保存眨眼掩码到磁盘
    blink_path = os.path.join(cache_dir, "blink.npy")
    np.save(blink_path, extended_blink)
    
    # Debug: 打印眨眼统计
    print(f"[Debug] Blink detection: {np.sum(extended_blink)}/{len(extended_blink)} frames ({100*np.mean(extended_blink):.1f}%)")
    
    # 计算有效帧索引 (使用 memmap)
    valid_mmap = np.memmap(valid_path, dtype=bool, mode='r', shape=(total_extracted,))
    valid_arr = np.array(valid_mmap)
    invalid_mask = ~valid_arr | extended_blink
    print(f"[Debug] ROI extraction: {np.sum(valid_arr)}/{len(valid_arr)} valid ({100*np.mean(valid_arr):.1f}%)")
    print(f"[Debug] Final valid (non-blink + ROI ok): {np.sum(~invalid_mask)}/{len(invalid_mask)} ({100*np.mean(~invalid_mask):.1f}%)")
    del valid_mmap, valid_arr
    valid_indices = np.where(~invalid_mask)[0]
    del invalid_mask, extended_blink
    gc.collect()
    
    if progress_callback:
        progress_callback(0.35)
    
    # ========== 阶段3: 分批推理，结果写入磁盘 (使用双缓冲预加载) ==========
    from concurrent.futures import ThreadPoolExecutor
    import threading
    
    gaze_path = os.path.join(cache_dir, "gaze.npy")
    gaze_results = np.memmap(gaze_path, dtype=np.float32, mode='w+', shape=(total_extracted, 3))
    gaze_results[:] = np.nan
    
    def load_batch_rois(indices):
        """后台线程加载 ROI"""
        rois = []
        for idx in indices:
            roi_file = os.path.join(roi_dir, f"{idx}.pt")
            roi_tensor = torch.load(roi_file, weights_only=True)
            rois.append(roi_tensor)
        return torch.stack(rois)
    
    if len(valid_indices) > 0:
        # 预计算所有 batch 的索引
        batches = []
        for batch_start in range(0, len(valid_indices), batch_size):
            batch_end = min(batch_start + batch_size, len(valid_indices))
            batches.append(valid_indices[batch_start:batch_end])
        
        with torch.no_grad():
            executor = ThreadPoolExecutor(max_workers=1)
            
            # 预加载第一批
            current_future = executor.submit(load_batch_rois, batches[0])
            
            for i, batch_indices in enumerate(batches):
                # 获取当前批次 (已预加载)
                batch_tensors = current_future.result().to(device)
                
                # 同时预加载下一批 (如果有)
                if i + 1 < len(batches):
                    next_future = executor.submit(load_batch_rois, batches[i + 1])
                
                # GPU 推理
                outputs = gaze_model(batch_tensors)
                predictions = outputs.cpu().numpy()
                del batch_tensors, outputs
                
                # 归一化
                norms = np.linalg.norm(predictions, axis=1, keepdims=True) + 1e-8
                predictions = predictions / norms
                
                # 写入 memmap
                gaze_results[batch_indices] = predictions
                del predictions
                
                # 切换到下一个 future
                if i + 1 < len(batches):
                    current_future = next_future
                
                if progress_callback:
                    progress = 0.35 + ((i + 1) / len(batches)) * 0.5
                    progress_callback(min(progress, 0.85))
            
            executor.shutdown(wait=False)
        
        # 最后刷新一次
        gaze_results.flush()
    
    # 清理ROI目录 (已经不需要了)
    shutil.rmtree(roi_dir, ignore_errors=True)
    
    if progress_callback:
        progress_callback(0.87)
    
    # ========== 阶段4: 信号处理与分析 (尽量避免大数组复制) ==========
    time_arr = np.arange(total_extracted, dtype=np.float32) / fps
    
    # 从磁盘加载 gaze 结果
    gaze_mmap = np.memmap(gaze_path, dtype=np.float32, mode='r', shape=(total_extracted, 3))
    gaze_arr = np.array(gaze_mmap)  # 必须复制，因为信号处理需要可写
    del gaze_mmap
    gc.collect()
    
    # 在插值之前，计算基于 NaN 的眨眼掩码（与 gui_visualizer 一致）
    # 这个掩码标记了所有没有有效 gaze 数据的帧（包括眨眼帧和 ROI 提取失败的帧）
    blink_mask_from_nan = np.isnan(gaze_arr).any(axis=1)
    print(f"[Debug] Blink mask from NaN (before interpolation): {np.sum(blink_mask_from_nan)}/{len(blink_mask_from_nan)} ({100*np.mean(blink_mask_from_nan):.1f}%)")

    processor = SignalProcessor(fps=fps)
    smoothed_gaze = processor.process(gaze_arr) if len(gaze_arr) > 0 else gaze_arr.copy()
    
    # 立即释放 gaze_arr，只保留 smoothed
    del gaze_arr
    gc.collect()
    
    # 只计算 smooth_angles (raw_angles 可以从 smooth 重建，不单独存)
    smooth_angles = vector_to_pitch_yaw(smoothed_gaze) if len(smoothed_gaze) > 0 else np.array([])
    del smoothed_gaze
    gc.collect()

    if progress_callback:
        progress_callback(0.90)

    # 使用基于 NaN 的眨眼掩码（与 gui_visualizer 一致）
    # 不再使用基于 EAR 的 extended_blink，因为 gui_visualizer 使用的是基于 NaN 的掩码
    extended_blink = blink_mask_from_nan

    # 拐点检测
    inflection_detector = InflectionPointDetector()
    pitch_inflections = {}
    yaw_inflections = {}
    if len(smooth_angles) > 0:
        pitch_inflections = inflection_detector.detect(smooth_angles[:, 0], fps)
        yaw_inflections = inflection_detector.detect(smooth_angles[:, 1], fps)

    # 眼震检测 - 使用完整分析器 (需要连续3个以上模式才算存在眼震)
    nystagmus_analyzer = NystagmusAnalyzer(fps=fps)
    nystagmus_results = {}
    if len(smooth_angles) > 0:
        # Debug info
        print(f"[Nystagmus] Input: fps={fps}, frames={len(smooth_angles)}, time_arr={len(time_arr)}, blink_mask={len(extended_blink)}")
        print(f"[Nystagmus] blink_frames={np.sum(extended_blink)}, valid_ratio={100*(1-np.mean(extended_blink)):.1f}%")
        print(f"[Nystagmus] Yaw range: {np.nanmin(smooth_angles[:, 1]):.2f} ~ {np.nanmax(smooth_angles[:, 1]):.2f}")
        print(f"[Nystagmus] Pitch range: {np.nanmin(smooth_angles[:, 0]):.2f} ~ {np.nanmax(smooth_angles[:, 0]):.2f}")
        
        # 检查 NaN 比例（经过 SignalProcessor 插值后应该没有 NaN）
        nan_ratio = np.mean(np.isnan(smooth_angles))
        print(f"[Nystagmus] NaN ratio after interpolation: {100*nan_ratio:.1f}%")
        
        # 检查非眨眼帧的数据
        valid_yaw = smooth_angles[~extended_blink, 1]
        print(f"[Nystagmus] Valid Yaw samples: {len(valid_yaw)}, range: {np.min(valid_yaw):.2f} ~ {np.max(valid_yaw):.2f}")
        
        # 水平眼震 (Yaw)
        horizontal_analysis = nystagmus_analyzer.analyze(
            time_arr, smooth_angles[:, 1], extended_blink, axis="horizontal"
        )
        # 垂直眼震 (Pitch)
        vertical_analysis = nystagmus_analyzer.analyze(
            time_arr, smooth_angles[:, 0], extended_blink, axis="vertical"
        )
        
        # Debug results
        if horizontal_analysis.get('success'):
            print(f"[Nystagmus H] patterns={horizontal_analysis.get('n_patterns', 0)}, "
                  f"filtered={horizontal_analysis.get('n_filtered_patterns', 0)}, "
                  f"has_nystagmus={horizontal_analysis.get('has_nystagmus', False)}, "
                  f"direction={horizontal_analysis.get('direction', 'unknown')}")
        else:
            print(f"[Nystagmus H] Failed: {horizontal_analysis.get('error', 'unknown')}")
        
        if vertical_analysis.get('success'):
            print(f"[Nystagmus V] patterns={vertical_analysis.get('n_patterns', 0)}, "
                  f"filtered={vertical_analysis.get('n_filtered_patterns', 0)}, "
                  f"has_nystagmus={vertical_analysis.get('has_nystagmus', False)}, "
                  f"direction={vertical_analysis.get('direction', 'unknown')}")
        
        # 构建结果 (与之前NystagmusDetector格式兼容)
        h_present = horizontal_analysis.get('has_nystagmus', False) if horizontal_analysis.get('success') else False
        v_present = vertical_analysis.get('has_nystagmus', False) if vertical_analysis.get('success') else False
        
        h_direction = horizontal_analysis.get('direction', 'unknown') if horizontal_analysis.get('success') else 'unknown'
        v_direction = vertical_analysis.get('direction', 'unknown') if vertical_analysis.get('success') else 'unknown'
        
        # 方向标签映射
        h_direction_label = {"left": "向左", "right": "向右"}.get(h_direction, "无")
        v_direction_label = {"up": "向上", "down": "向下"}.get(v_direction, "无")
        
        nystagmus_results = {
            "horizontal": {
                "present": h_present,
                "direction": h_direction,
                "direction_label": h_direction_label,
                "n_patterns": horizontal_analysis.get('n_patterns', 0) if horizontal_analysis.get('success') else 0,
                "spv": horizontal_analysis.get('spv', 0) if horizontal_analysis.get('success') else 0,
                "cv": horizontal_analysis.get('cv', 0) if horizontal_analysis.get('success') else 0,
            },
            "vertical": {
                "present": v_present,
                "direction": v_direction,
                "direction_label": v_direction_label,
                "n_patterns": vertical_analysis.get('n_patterns', 0) if vertical_analysis.get('success') else 0,
                "spv": vertical_analysis.get('spv', 0) if vertical_analysis.get('success') else 0,
                "cv": vertical_analysis.get('cv', 0) if vertical_analysis.get('success') else 0,
            },
            # 详细分析结果
            "horizontal_analysis": horizontal_analysis,
            "vertical_analysis": vertical_analysis,
        }
        
        # 生成总结
        if not h_present and not v_present:
            nystagmus_results["summary"] = "未检测到明显眼震 (需连续≥3个眼震模式)"
        elif h_present and not v_present:
            nystagmus_results["summary"] = f"检测到水平眼震，快相方向: {h_direction_label} ({horizontal_analysis.get('n_patterns', 0)}个连续模式)"
        elif v_present and not h_present:
            nystagmus_results["summary"] = f"检测到垂直眼震，快相方向: {v_direction_label} ({vertical_analysis.get('n_patterns', 0)}个连续模式)"
        else:
            nystagmus_results["summary"] = f"检测到混合眼震 - 水平({h_direction_label}) + 垂直({v_direction_label})"

    if progress_callback:
        progress_callback(1.0)

    elapsed = time.time() - start_time
    blink_count = int(np.sum(extended_blink))
    
    # 构建返回结果 (只保留必要数据，节省内存)
    result = {
        "fps": fps,
        "frames": total_extracted,
        "duration": elapsed,
        "video_duration": total_extracted / fps if fps > 0 else 0,
        "time": time_arr,
        "gaze_angles_smooth": smooth_angles,  # 只保留平滑后的角度
        "blink_mask": extended_blink,
        "blink_count": blink_count,
        "valid_frames": len(valid_indices),
        "pitch_inflections": pitch_inflections,
        "yaw_inflections": yaw_inflections,
        "nystagmus": nystagmus_results,
    }
    
    # 清理所有缓存文件
    shutil.rmtree(cache_dir, ignore_errors=True)
    
    return result


def get_gif_dir() -> str:
    """获取 GIF 保存目录 (使用 static 目录以便 Streamlit 静态文件服务)"""
    gif_dir = os.path.join(os.path.dirname(__file__), "static", "gif")
    os.makedirs(gif_dir, exist_ok=True)
    return gif_dir


def get_report_dir() -> str:
    """获取报告保存目录 (使用 static 目录以便 Streamlit 静态文件服务)"""
    report_dir = os.path.join(os.path.dirname(__file__), "static", "report")
    os.makedirs(report_dir, exist_ok=True)
    return report_dir


def cleanup_temp_files():
    """清理临时文件（GIF 和 PDF 报告）"""
    for folder in ["gif", "report"]:
        folder_path = os.path.join(os.path.dirname(__file__), "static", folder)
        if os.path.exists(folder_path):
            for f in os.listdir(folder_path):
                try:
                    os.remove(os.path.join(folder_path, f))
                except Exception:
                    pass


def extract_nystagmus_gif(video_path: str, results: Dict[str, Any], padding: float = 0.3) -> Optional[str]:
    """
    从检测到的眼震模式中提取眼部 ROI 的增强 GIF
    
    Args:
        video_path: 原始视频路径
        results: process_video 返回的结果
        padding: 前后扩展时间（秒）
    
    Returns:
        GIF 文件路径，如果没有眼震则返回 None
    """
    from PIL import Image, ImageEnhance
    
    nystagmus = results.get("nystagmus", {})
    fps = results.get("fps", 30)
    
    # 收集所有眼震 patterns
    all_patterns = []
    
    h_analysis = nystagmus.get("horizontal_analysis", {})
    if h_analysis.get("has_nystagmus"):
        patterns = h_analysis.get("patterns", [])
        all_patterns.extend(patterns)
    
    v_analysis = nystagmus.get("vertical_analysis", {})
    if v_analysis.get("has_nystagmus"):
        patterns = v_analysis.get("patterns", [])
        all_patterns.extend(patterns)
    
    if not all_patterns:
        return None
    
    # 选择振幅最大的 pattern 作为典型示例
    best_pattern = max(all_patterns, key=lambda p: p.get('amplitude', 0))
    
    # 计算时间范围
    center_time = best_pattern.get('time_point', 0)
    duration = best_pattern.get('total_time', 0.5)
    
    # 扩展时间范围
    start_time = max(0, center_time - duration - padding)
    end_time = center_time + duration + padding
    
    # 读取视频
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return None
    
    video_fps = cap.get(cv2.CAP_PROP_FPS) or fps
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    video_duration = total_frames / video_fps
    
    end_time = min(end_time, video_duration)
    start_frame = int(start_time * video_fps)
    end_frame = int(end_time * video_fps)
    
    # 初始化眼部提取器
    eye_normalizer = SingleEyeNormalizer(
        eye="left",
        target_size=(72, 120),  # 放大尺寸以便 GIF 显示
        enhance_gamma=1.2,
        enhance_clahe_clip=2.0,
    )
    
    # 收集眼部帧
    frames = []
    cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)
    
    # 采样到约 15fps
    target_gif_fps = 15
    frame_skip = max(1, int(video_fps / target_gif_fps))
    
    # CLAHE 增强器
    clahe = cv2.createCLAHE(clipLimit=2.5, tileGridSize=(4, 4))
    
    frame_idx = 0
    for _ in range(end_frame - start_frame):
        ret, frame = cap.read()
        if not ret:
            break
        
        if frame_idx % frame_skip == 0:
            # 提取眼部 ROI
            roi_tensor, ear = eye_normalizer.extract(frame)
            
            if roi_tensor is not None:
                # 转换 tensor 回 numpy 图像
                roi_np = roi_tensor.squeeze().numpy()
                
                # 如果是单通道，转换为 3 通道
                if roi_np.ndim == 2:
                    roi_np = (roi_np * 255).astype(np.uint8)
                else:
                    roi_np = (roi_np.transpose(1, 2, 0) * 255).astype(np.uint8)
                
                # 增强亮度和对比度
                if roi_np.ndim == 2:
                    # 灰度图
                    enhanced = clahe.apply(roi_np)
                    # 提高亮度
                    enhanced = cv2.convertScaleAbs(enhanced, alpha=1.3, beta=30)
                    roi_rgb = cv2.cvtColor(enhanced, cv2.COLOR_GRAY2RGB)
                else:
                    # 彩色图 - 转换到 LAB 空间增强
                    lab = cv2.cvtColor(roi_np, cv2.COLOR_RGB2LAB)
                    l, a, b = cv2.split(lab)
                    l = clahe.apply(l)
                    l = cv2.convertScaleAbs(l, alpha=1.2, beta=20)
                    lab = cv2.merge([l, a, b])
                    roi_rgb = cv2.cvtColor(lab, cv2.COLOR_LAB2RGB)
                
                # 放大以便在 GIF 中显示
                h, w = roi_rgb.shape[:2]
                scale = 2.5
                new_w, new_h = int(w * scale), int(h * scale)
                roi_rgb = cv2.resize(roi_rgb, (new_w, new_h), interpolation=cv2.INTER_CUBIC)
                
                frames.append(Image.fromarray(roi_rgb))
        
        frame_idx += 1
    
    cap.release()
    
    if not frames:
        return None
    
    # 生成 GIF
    gif_dir = get_gif_dir()
    gif_filename = f"nystagmus_{datetime.now().strftime('%Y%m%d_%H%M%S')}.gif"
    gif_path = os.path.join(gif_dir, gif_filename)
    
    frame_duration = int(1000 / target_gif_fps)
    frames[0].save(
        gif_path,
        save_all=True,
        append_images=frames[1:],
        duration=frame_duration,
        loop=0
    )
    
    return gif_path


# ==============================================================================
#  PDF报告生成 - 中文版
# ==============================================================================
class MedicalReportGenerator:
    """医学PDF报告生成器 (中文)"""
    
    def __init__(self):
        self.has_chinese_font = register_chinese_font()
        self.font_name = CHINESE_FONT_NAME if self.has_chinese_font else 'Helvetica'
        self.styles = getSampleStyleSheet()
        self._setup_styles()
    
    def _setup_styles(self):
        """设置自定义样式"""
        # 标题样式
        self.styles.add(ParagraphStyle(
            name='ReportTitle',
            fontSize=26,
            leading=36,
            alignment=TA_CENTER,
            spaceAfter=15,
            fontName=self.font_name,
        ))
        
        # 节标题
        self.styles.add(ParagraphStyle(
            name='SectionTitle',
            fontSize=14,
            leading=20,
            spaceBefore=18,
            spaceAfter=12,
            fontName=self.font_name,
            textColor=colors.HexColor('#2C3E50'),
        ))
        
        # 正文
        self.styles.add(ParagraphStyle(
            name='ReportBody',
            fontSize=11,
            leading=16,
            alignment=TA_LEFT,
            spaceAfter=8,
            fontName=self.font_name,
        ))
        
        # 结论样式
        self.styles.add(ParagraphStyle(
            name='Conclusion',
            fontSize=12,
            leading=18,
            alignment=TA_LEFT,
            spaceBefore=10,
            spaceAfter=10,
            fontName=self.font_name,
            backColor=colors.HexColor('#F8F9FA'),
            borderPadding=10,
        ))
    
    def _create_nystagmus_plot(self, analysis: Dict[str, Any], axis_name: str) -> Optional[io.BytesIO]:
        """
        生成眼震拐点分析图
        - 绿色线段：普通拐点连线
        - 红色线段：快相
        - 蓝色线段：慢相
        """
        if not analysis or not analysis.get('success'):
            return None
        
        time = analysis.get('time', np.array([]))
        signal = analysis.get('filtered_signal', np.array([]))
        tp = analysis.get('turning_points', np.array([]))
        patterns = analysis.get('patterns', [])
        
        if len(time) == 0 or len(signal) == 0:
            return None
        
        fig, ax = plt.subplots(figsize=(10, 3.5), dpi=150)
        
        # 先画所有绿色拐点连线（基线）
        if len(tp) > 0:
            ax.plot(time[tp], signal[tp], color='#27AE60', linewidth=1.5, zorder=1)
            ax.plot(time[tp], signal[tp], 'o', color='#27AE60', markersize=3, zorder=2)
        
        # 在眼震模式上覆盖快慢相线段
        first_fast = True
        first_slow = True
        for pattern in patterns:
            idx = pattern.get('index', 0)
            if idx > 0 and idx + 1 < len(tp):
                tp1 = tp[idx - 1]  # 第一个拐点
                tp2 = tp[idx]      # 中间拐点（峰值）
                tp3 = tp[idx + 1]  # 第三个拐点
                
                if pattern.get('fast_phase_first', True):
                    # 快相: tp1 -> tp2, 慢相: tp2 -> tp3
                    fast_label = '快相' if first_fast else None
                    slow_label = '慢相' if first_slow else None
                    ax.plot([time[tp1], time[tp2]], [signal[tp1], signal[tp2]], 
                           color='#E74C3C', linewidth=2.5, zorder=3, label=fast_label)
                    ax.plot([time[tp2], time[tp3]], [signal[tp2], signal[tp3]], 
                           color='#3498DB', linewidth=2.5, zorder=3, label=slow_label)
                else:
                    # 慢相: tp1 -> tp2, 快相: tp2 -> tp3
                    slow_label = '慢相' if first_slow else None
                    fast_label = '快相' if first_fast else None
                    ax.plot([time[tp1], time[tp2]], [signal[tp1], signal[tp2]], 
                           color='#3498DB', linewidth=2.5, zorder=3, label=slow_label)
                    ax.plot([time[tp2], time[tp3]], [signal[tp2], signal[tp3]], 
                           color='#E74C3C', linewidth=2.5, zorder=3, label=fast_label)
                
                first_fast = False
                first_slow = False
        
        # 标题
        direction = analysis.get('direction', 'unknown')
        spv = analysis.get('spv', 0)
        n_patterns = analysis.get('n_patterns', 0)
        has_nystagmus = analysis.get('has_nystagmus', False)
        
        dir_map = {'left': '向左', 'right': '向右', 'up': '向上', 'down': '向下', 
                   'bidirectional': '双向', 'none': '无', 'unknown': '—'}
        dir_label = dir_map.get(direction, '—')
        
        if has_nystagmus:
            title = f'{axis_name}眼动 | 检出眼震 | 方向: {dir_label} | SPV: {spv:.1f}°/s | 模式: {n_patterns}'
        else:
            title = f'{axis_name}眼动 | 未检出眼震'
        
        ax.set_title(title, fontsize=11, fontweight='bold')
        ax.set_xlabel('时间 (s)', fontsize=10)
        ax.set_ylabel('角度 (°)', fontsize=10)
        if patterns:  # 只有有眼震模式时才显示图例
            ax.legend(loc='upper right', fontsize=8)
        ax.grid(True, alpha=0.2)
        ax.spines['top'].set_visible(False)
        ax.spines['right'].set_visible(False)
        
        plt.tight_layout()
        
        buf = io.BytesIO()
        fig.savefig(buf, format='png', bbox_inches='tight', dpi=150)
        buf.seek(0)
        plt.close(fig)
        
        return buf
    
    def generate(self, results: Dict[str, Any], patient_info: Dict[str, str] = None) -> bytes:
        """生成PDF医学报告（精简版）"""
        buffer = io.BytesIO()
        doc = SimpleDocTemplate(
            buffer,
            pagesize=A4,
            rightMargin=2*cm,
            leftMargin=2*cm,
            topMargin=1.5*cm,
            bottomMargin=1.5*cm,
        )
        
        story = []
        
        # ===== 报告标题 =====
        story.append(Paragraph("眼震检测报告", self.styles['ReportTitle']))
        story.append(HRFlowable(width="100%", thickness=2, color=colors.HexColor('#2C3E50'), spaceAfter=15))
        
        # ===== 检查信息 =====
        now = datetime.now()
        report_time = f"{now.year}-{now.month:02d}-{now.day:02d} {now.hour:02d}:{now.minute:02d}"
        video_duration = results.get("video_duration", 0)
        fps = results.get('fps', 30)
        
        info_data = [
            ["检查时间", report_time, "视频时长", f"{video_duration:.1f}s"],
            ["采样率", f"{fps:.0f} Hz", "有效帧", f"{results.get('valid_frames', 0)}帧"],
        ]
        
        if patient_info:
            if patient_info.get("name") or patient_info.get("id"):
                name = patient_info.get("name", "—")
                pid = patient_info.get("id", "—")
                info_data.insert(0, ["患者", name, "ID", pid])
        
        info_table = Table(info_data, colWidths=[2.5*cm, 4.5*cm, 2.5*cm, 4.5*cm])
        info_table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (0, -1), colors.HexColor('#F4F6F7')),
            ('BACKGROUND', (2, 0), (2, -1), colors.HexColor('#F4F6F7')),
            ('FONTNAME', (0, 0), (-1, -1), self.font_name),
            ('FONTSIZE', (0, 0), (-1, -1), 9),
            ('BOTTOMPADDING', (0, 0), (-1, -1), 6),
            ('TOPPADDING', (0, 0), (-1, -1), 6),
            ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#D5D8DC')),
        ]))
        story.append(info_table)
        story.append(Spacer(1, 15))
        
        # ===== 眼震检测结论 =====
        nystagmus = results.get("nystagmus", {})
        h_result = nystagmus.get("horizontal", {})
        v_result = nystagmus.get("vertical", {})
        
        h_present = h_result.get("present", False)
        v_present = v_result.get("present", False)
        
        # 结论框
        if h_present or v_present:
            conclusion_color = '#FADBD8'  # 浅红色
            conclusion_text = "<b>检测结论: 存在眼震</b>"
            if h_present and v_present:
                conclusion_text += f"<br/>· 水平眼震: {h_result.get('direction_label', '—')}, SPV {h_result.get('spv', 0):.1f}°/s"
                conclusion_text += f"<br/>· 垂直眼震: {v_result.get('direction_label', '—')}, SPV {v_result.get('spv', 0):.1f}°/s"
            elif h_present:
                conclusion_text += f"<br/>· 水平眼震: 快相{h_result.get('direction_label', '—')}, SPV {h_result.get('spv', 0):.1f}°/s, {h_result.get('n_patterns', 0)}个连续模式"
            else:
                conclusion_text += f"<br/>· 垂直眼震: 快相{v_result.get('direction_label', '—')}, SPV {v_result.get('spv', 0):.1f}°/s, {v_result.get('n_patterns', 0)}个连续模式"
        else:
            conclusion_color = '#D5F5E3'  # 浅绿色
            conclusion_text = "<b>检测结论: 未检出眼震</b>"
        
        conclusion_style = ParagraphStyle(
            name='ConclusionBox',
            fontSize=11,
            leading=16,
            fontName=self.font_name,
            backColor=colors.HexColor(conclusion_color),
            borderPadding=12,
        )
        story.append(Paragraph(conclusion_text, conclusion_style))
        story.append(Spacer(1, 15))
        
        # ===== 水平眼动图 =====
        h_analysis = nystagmus.get("horizontal_analysis", {})
        h_plot = self._create_nystagmus_plot(h_analysis, "水平")
        if h_plot:
            story.append(RLImage(h_plot, width=16*cm, height=5.6*cm))
            story.append(Spacer(1, 10))
        
        # ===== 垂直眼动图 =====
        v_analysis = nystagmus.get("vertical_analysis", {})
        v_plot = self._create_nystagmus_plot(v_analysis, "垂直")
        if v_plot:
            story.append(RLImage(v_plot, width=16*cm, height=5.6*cm))
            story.append(Spacer(1, 10))
        
        # ===== 详细数据表 =====
        story.append(Paragraph("检测参数", self.styles['SectionTitle']))
        
        detail_data = [
            ["指标", "水平方向", "垂直方向"],
            ["眼震检出", "是" if h_present else "否", "是" if v_present else "否"],
            ["快相方向", h_result.get('direction_label', '—'), v_result.get('direction_label', '—')],
            ["眼震模式数", str(h_result.get('n_patterns', 0)), str(v_result.get('n_patterns', 0))],
            ["慢相速度(SPV)", f"{h_result.get('spv', 0):.1f}°/s", f"{v_result.get('spv', 0):.1f}°/s"],
            ["变异系数(CV)", f"{h_result.get('cv', 0):.0f}%", f"{v_result.get('cv', 0):.0f}%"],
        ]
        
        detail_table = Table(detail_data, colWidths=[5*cm, 4.5*cm, 4.5*cm])
        detail_table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#2C3E50')),
            ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
            ('BACKGROUND', (0, 1), (0, -1), colors.HexColor('#F4F6F7')),
            ('ALIGN', (1, 0), (-1, -1), 'CENTER'),
            ('FONTNAME', (0, 0), (-1, -1), self.font_name),
            ('FONTSIZE', (0, 0), (-1, -1), 9),
            ('BOTTOMPADDING', (0, 0), (-1, -1), 7),
            ('TOPPADDING', (0, 0), (-1, -1), 7),
            ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#BDC3C7')),
            # 眼震检出行的颜色
            ('BACKGROUND', (1, 1), (1, 1), colors.HexColor('#FADBD8') if h_present else colors.HexColor('#D5F5E3')),
            ('BACKGROUND', (2, 1), (2, 1), colors.HexColor('#FADBD8') if v_present else colors.HexColor('#D5F5E3')),
        ]))
        story.append(detail_table)
        
        doc.build(story)
        pdf_bytes = buffer.getvalue()
        buffer.close()
        
        return pdf_bytes


# ==============================================================================
#  Streamlit UI - 极简设计
# ==============================================================================
def main():
    st.set_page_config(
        page_title="VertiWisdom",
        page_icon="👁️",
        layout="centered",
        initial_sidebar_state="collapsed",
    )
    
    # session_state 初始化（清理逻辑移到程序启动入口）
    if "app_initialized" not in st.session_state:
        st.session_state.app_initialized = True
    if "analysis_progress" not in st.session_state:
        st.session_state.analysis_progress = None  # None=未开始, 0-1=进行中, "done"=完成
    
    # 自定义CSS - 极简美学 + 眼球图标
    st.markdown("""
    <style>
        [data-testid="stSidebar"] { display: none; }
        #MainMenu {visibility: hidden;}
        footer {visibility: hidden;}
        header {visibility: hidden;}
        
        .main .block-container {
            max-width: 800px;
            padding-top: 3rem;
            padding-bottom: 3rem;
        }
        
        .title-container {
            text-align: center;
            padding: 2rem 0 1rem 0;
        }
        
        /* 眼球图标 */
        .eye-icon {
            display: inline-block;
            width: 50px;
            height: 50px;
            position: relative;
            vertical-align: middle;
            margin-right: 12px;
        }
        
        .eye-outer {
            width: 50px;
            height: 30px;
            background: linear-gradient(180deg, #f5f5f5 0%, #e8e8e8 100%);
            border-radius: 50%;
            position: absolute;
            top: 50%;
            transform: translateY(-50%);
            box-shadow: inset 0 2px 8px rgba(0,0,0,0.15);
            overflow: hidden;
        }
        
        .eye-iris {
            width: 22px;
            height: 22px;
            background: radial-gradient(circle at 35% 35%, #8B7355 0%, #5D4E37 50%, #3D2E1F 100%);
            border-radius: 50%;
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            box-shadow: inset 0 0 10px rgba(0,0,0,0.3);
        }
        
        .eye-pupil {
            width: 10px;
            height: 10px;
            background: radial-gradient(circle at 30% 30%, #333 0%, #000 100%);
            border-radius: 50%;
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
        }
        
        .eye-highlight {
            width: 4px;
            height: 4px;
            background: white;
            border-radius: 50%;
            position: absolute;
            top: 35%;
            left: 35%;
        }
        
        .main-title {
            display: inline-block;
            font-size: 2.8rem;
            font-weight: 700;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
            vertical-align: middle;
            font-family: 'SF Pro Display', -apple-system, BlinkMacSystemFont, sans-serif;
        }
        
        .subtitle {
            font-size: 1rem;
            color: #6B7280;
            font-weight: 400;
            letter-spacing: 0.5px;
            margin-top: 0.5rem;
        }
        
        .stFileUploader { margin-top: 2rem; }
        
        .stFileUploader > div > div {
            border: 2px dashed #D1D5DB;
            border-radius: 16px;
            padding: 3rem 2rem;
            background: linear-gradient(180deg, #FAFAFA 0%, #F3F4F6 100%);
            transition: all 0.3s ease;
        }
        
        .stFileUploader > div > div:hover {
            border-color: #667eea;
            background: linear-gradient(180deg, #F8F9FF 0%, #F0F1FF 100%);
        }
        
        .stButton > button {
            width: 100%;
            padding: 0.8rem 2rem;
            font-size: 1.1rem;
            font-weight: 600;
            border-radius: 12px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            transition: all 0.3s ease;
            margin-top: 1rem;
        }
        
        .stButton > button:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 30px rgba(102, 126, 234, 0.4);
        }
        
        .stDownloadButton > button {
            width: 100%;
            padding: 1rem 2rem;
            font-size: 1.1rem;
            font-weight: 600;
            border-radius: 12px;
            background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);
            color: white;
            border: none;
            margin-top: 1.5rem;
        }
        
        .stProgress > div > div {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        }
        
        /* 简化的结果预览 */
        .result-summary {
            background: linear-gradient(135deg, #f8f9fa 0%, #e9ecef 100%);
            border-radius: 12px;
            padding: 1rem 1.5rem;
            margin-top: 1rem;
            font-size: 0.95rem;
            color: #495057;
        }
        
        .result-item {
            display: inline-block;
            margin-right: 2rem;
        }
        
        .result-label {
            color: #6c757d;
            font-size: 0.8rem;
        }
        
        .result-value {
            font-weight: 600;
            color: #212529;
        }
        
        .result-positive { color: #dc3545; }
        .result-negative { color: #28a745; }
        
        .viewerBadge_container__1QSob { display: none; }
    </style>
    """, unsafe_allow_html=True)
    
    # 标题区域 - 带眼球图标
    st.markdown("""
    <div class="title-container">
        <div class="eye-icon">
            <div class="eye-outer">
                <div class="eye-iris">
                    <div class="eye-pupil">
                        <div class="eye-highlight"></div>
                    </div>
                </div>
            </div>
        </div>
        <span class="main-title">VertiWisdom</span>
        <div class="subtitle">AI-Powered Eye Movement Analysis</div>
    </div>
    """, unsafe_allow_html=True)
    
    # 简介
    st.markdown("""
    <p style="text-align: center; color: #9CA3AF; font-size: 0.95rem; margin: 1.5rem 0 2rem 0;">
        上传眼动视频，自动生成专业医学报告
    </p>
    """, unsafe_allow_html=True)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    default_gaze_paths = [
        "checkpoints/gaze/checkpoint_best.pth",
        "checkpoints/gaze/checkpoint_latest.pth",
        "checkpoints/checkpoint_best.pth",
        "checkpoints/checkpoint_latest.pth",
    ]

    def first_existing(paths):
        for p in paths:
            if os.path.exists(p):
                return p
        return ""

    gaze_ckpt = first_existing(default_gaze_paths)

    if not gaze_ckpt:
        st.error("⚠️ 未找到模型文件，请检查 checkpoints 目录")
        return

    # 不限制文件类型（解决 iOS/iPadOS 无法选择 MKV 的问题）
    uploaded = st.file_uploader(
        "拖放视频文件或点击上传",
        type=None,
        help="支持 MP4, MKV, AVI, MOV 格式",
        label_visibility="collapsed",
    )
    
    if "analysis_results" not in st.session_state:
        st.session_state.analysis_results = None
    if "pdf_path" not in st.session_state:
        st.session_state.pdf_path = None
    if "gif_path" not in st.session_state:
        st.session_state.gif_path = None

    if uploaded:
        # 检查文件扩展名
        allowed_extensions = {'.mp4', '.mkv', '.avi', '.mov', '.webm', '.m4v'}
        file_ext = os.path.splitext(uploaded.name)[1].lower()
        
        if file_ext not in allowed_extensions:
            st.error(f"❌ 不支持的文件格式: {file_ext}\n\n请上传 MP4, MKV, AVI, MOV 等视频文件")
        else:
            tmp_dir = tempfile.mkdtemp(prefix="vertiwisdom_")
            video_path = os.path.join(tmp_dir, uploaded.name)
            with open(video_path, "wb") as f:
                f.write(uploaded.read())
            
            # 左边按钮，右边进度条
            btn_col, progress_col = st.columns([1, 2])
            
            with btn_col:
                start_clicked = st.button("🔬 开始分析")
            
            with progress_col:
                progress_placeholder = st.empty()
            
            if start_clicked:
                st.session_state.analysis_progress = 0
                
                with st.spinner("正在加载模型..."):
                    gaze_model = load_gaze_model(gaze_ckpt, device)
                
                def update_progress(p):
                    st.session_state.analysis_progress = p
                    progress_placeholder.markdown(f"""
                    <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                                border-radius: 12px; padding: 0.55rem 1rem; margin-top: 1px;">
                        <div style="color: white; font-weight: 600; font-size: 0.85rem; display: flex; align-items: center; gap: 0.5rem;">
                            <span>🔬 {int(p*100)}%</span>
                            <div style="flex: 1; background: rgba(255,255,255,0.3); border-radius: 4px; height: 6px; overflow: hidden;">
                                <div style="background: white; height: 100%; width: {int(p*100)}%; 
                                            border-radius: 4px; transition: width 0.3s ease;"></div>
                            </div>
                        </div>
                    </div>
                    """, unsafe_allow_html=True)
                
                update_progress(0)
                
                # 根据是否有GPU设置batch_size (GPU显存充足，可大幅提升)
                batch_size = 3840 if device.type == 'cuda' else 16
                
                results = process_video(
                    video_path=video_path,
                    gaze_model=gaze_model,
                    device=device,
                    batch_size=batch_size,
                    progress_callback=update_progress,
                )

                # 显示完成状态
                progress_placeholder.markdown(f"""
                <div style="background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);
                            border-radius: 12px; padding: 0.55rem 1rem; margin-top: 1px;">
                    <div style="color: white; font-weight: 600; font-size: 0.85rem;">
                        ✅ 完成 {results['frames']}帧 / {results['video_duration']:.1f}秒
                    </div>
                </div>
                """, unsafe_allow_html=True)
                
                with st.spinner("正在生成报告..."):
                    report_generator = MedicalReportGenerator()
                    pdf_bytes = report_generator.generate(results)
                    
                    # 保存 PDF 到 report 文件夹
                    report_dir = get_report_dir()
                    pdf_filename = f"report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
                    pdf_path = os.path.join(report_dir, pdf_filename)
                    with open(pdf_path, 'wb') as f:
                        f.write(pdf_bytes)
                
                # 提取典型眼震 GIF
                gif_path = extract_nystagmus_gif(video_path, results)
                
                st.session_state.analysis_results = results
                st.session_state.pdf_path = pdf_path
                st.session_state.gif_path = gif_path
                st.session_state.analysis_progress = "done"
    
    # 显示结果
    if st.session_state.pdf_path is not None and os.path.exists(st.session_state.pdf_path):
        # PDF 预览按钮 - 使用静态文件路径在新标签页打开
        pdf_filename = os.path.basename(st.session_state.pdf_path)
        pdf_url = f"/app/static/report/{pdf_filename}"
        
        st.markdown(f"""
        <a href="{pdf_url}" target="_blank" 
           style="text-decoration: none; display: block;">
            <div style="background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);
                        border-radius: 12px; padding: 1rem 1.5rem; margin: 1rem 0;
                        text-align: center; cursor: pointer;
                        transition: all 0.3s ease; box-shadow: 0 4px 15px rgba(17,153,142,0.3);"
                 onmouseover="this.style.transform='translateY(-2px)'; this.style.boxShadow='0 8px 25px rgba(17,153,142,0.4)';"
                 onmouseout="this.style.transform='translateY(0)'; this.style.boxShadow='0 4px 15px rgba(17,153,142,0.3)';">
                <span style="color: white; font-size: 1.1rem; font-weight: 600;">
                    📄 下载医学报告 (PDF)
                </span>
            </div>
        </a>
        """, unsafe_allow_html=True)
        
        # 结果预览 - 左右布局
        if st.session_state.analysis_results:
            results = st.session_state.analysis_results
            nystagmus = results.get("nystagmus", {})
            
            h_present = nystagmus.get("horizontal", {}).get("present", False)
            v_present = nystagmus.get("vertical", {}).get("present", False)
            has_nystagmus = h_present or v_present
            
            # 左右两栏布局
            if has_nystagmus and st.session_state.gif_path and os.path.exists(st.session_state.gif_path):
                col1, col2 = st.columns([1, 1])
            else:
                col1 = st.container()
                col2 = None
            
            # 左侧：眼震检测结果
            with col1:
                # 检测到=红色，未检测到=绿色
                h_color = "#dc3545" if h_present else "#28a745"
                v_color = "#dc3545" if v_present else "#28a745"
                h_text = "检出" if h_present else "未检出"
                v_text = "检出" if v_present else "未检出"
                
                st.markdown(f"""
                <div style="background: linear-gradient(135deg, #f8f9fa 0%, #e9ecef 100%); 
                            border-radius: 12px; padding: 1rem; margin-top: 0.5rem;">
                    <div style="display: flex; justify-content: space-around; text-align: center;">
                        <div>
                            <div style="font-size: 0.85rem; color: #6c757d; margin-bottom: 0.3rem;">水平眼震</div>
                            <div style="font-size: 1.2rem; font-weight: 700; color: {h_color};">{h_text}</div>
                        </div>
                        <div>
                            <div style="font-size: 0.85rem; color: #6c757d; margin-bottom: 0.3rem;">垂直眼震</div>
                            <div style="font-size: 1.2rem; font-weight: 700; color: {v_color};">{v_text}</div>
                        </div>
                    </div>
                </div>
                """, unsafe_allow_html=True)
            
            # 右侧：典型眼震 GIF
            if col2 is not None:
                with col2:
                    st.markdown("""
                    <div style="text-align: center; font-size: 0.85rem; color: #6c757d; margin-top: 0.5rem; margin-bottom: 0.3rem;">
                        典型眼震
                    </div>
                    """, unsafe_allow_html=True)
                    st.image(st.session_state.gif_path)


if __name__ == "__main__":
    # 程序启动时清理临时文件（只执行一次，不会在用户访问时重复执行）
    cleanup_temp_files()
    main()
