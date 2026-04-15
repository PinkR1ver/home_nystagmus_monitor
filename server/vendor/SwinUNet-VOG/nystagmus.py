"""
nystagmus.py - 眼震(Nystagmus)检测与分析模块

眼震特征:
- 水平眼震 (Horizontal Nystagmus): Yaw方向的周期性快慢相运动
- 垂直眼震 (Vertical Nystagmus): Pitch方向的周期性快慢相运动
- 眼震方向: 以快相方向定义 (左/右/上/下)

使用方法:
    from nystagmus import NystagmusAnalyzer, NystagmusDetector
    
    # 简单检测 (用于快速判断是否有眼震)
    detector = NystagmusDetector(fps=30.0)
    results = detector.detect(pitch_angles, yaw_angles)
    
    # 完整分析 (用于详细的眼震分析和可视化)
    analyzer = NystagmusAnalyzer(fps=30.0)
    results = analyzer.analyze(timestamps, angles, blink_mask, axis="horizontal")
"""

import numpy as np
import scipy.signal
from typing import Dict, Any, Tuple, List, Optional


# ==============================================================================
#  简化版眼震检测器 (用于快速检测)
# ==============================================================================
class NystagmusDetector:
    """
    简化版眼震检测器
    用于快速判断是否存在眼震及其基本特征
    
    适用场景:
    - PDF报告生成
    - 快速筛查
    - 实时检测
    """
    
    def __init__(self, fps: float = 30.0):
        self.fps = fps
        
        # 检测参数 (可调整)
        self.velocity_threshold = 5.0   # 度/秒，速度阈值
        self.min_amplitude = 2.0        # 度，最小振幅
        self.min_frequency = 0.5        # Hz，最小频率
        self.max_frequency = 6.0        # Hz，最大频率
        
    def compute_velocity(self, angles: np.ndarray) -> np.ndarray:
        """计算角速度 (度/秒)"""
        dt = 1.0 / self.fps
        velocity = np.gradient(angles, dt, axis=0)
        return velocity
    
    def analyze_direction(self, angles: np.ndarray, velocity: np.ndarray) -> Dict[str, Any]:
        """
        分析眼震方向
        眼震方向以快相方向定义
        """
        # 检测高速运动（快相）
        fast_phases_pos = velocity > self.velocity_threshold
        fast_phases_neg = velocity < -self.velocity_threshold
        
        # 计算正向和负向快相的数量
        pos_count = np.sum(fast_phases_pos)
        neg_count = np.sum(fast_phases_neg)
        
        if pos_count + neg_count == 0:
            return {"direction": "无", "confidence": 0.0}
        
        # 主导方向
        if pos_count > neg_count * 1.5:
            direction = "正向"
            confidence = pos_count / (pos_count + neg_count)
        elif neg_count > pos_count * 1.5:
            direction = "负向"
            confidence = neg_count / (pos_count + neg_count)
        else:
            direction = "双向"
            confidence = 0.5
            
        return {"direction": direction, "confidence": confidence}
    
    def compute_frequency(self, angles: np.ndarray) -> Dict[str, float]:
        """计算眼震频率特征"""
        if len(angles) < self.fps:
            return {"dominant_freq": 0.0, "power": 0.0}
        
        # FFT分析
        fft_result = np.fft.fft(angles - np.mean(angles))
        freqs = np.fft.fftfreq(len(angles), 1.0/self.fps)
        power = np.abs(fft_result) ** 2
        
        # 只看正频率且在感兴趣范围内
        mask = (freqs > self.min_frequency) & (freqs < self.max_frequency)
        if not np.any(mask):
            return {"dominant_freq": 0.0, "power": 0.0}
        
        relevant_power = power[mask]
        relevant_freqs = freqs[mask]
        
        dominant_idx = np.argmax(relevant_power)
        dominant_freq = relevant_freqs[dominant_idx]
        max_power = relevant_power[dominant_idx]
        
        return {"dominant_freq": abs(dominant_freq), "power": max_power}
    
    def detect(self, pitch: np.ndarray, yaw: np.ndarray) -> Dict[str, Any]:
        """
        主检测函数
        
        Args:
            pitch: 俯仰角数组 (垂直方向)
            yaw: 偏航角数组 (水平方向)
        
        Returns:
            {
                "horizontal": {
                    "present": bool,           # 是否存在水平眼震
                    "direction": str,          # 原始方向
                    "direction_label": str,    # 方向标签 (左/右/双向/无)
                    "amplitude": float,        # 振幅 (度)
                    "frequency": float,        # 主频 (Hz)
                    "confidence": float        # 置信度
                },
                "vertical": {...},
                "summary": str                 # 总结描述
            }
        """
        results = {
            "horizontal": self._analyze_single_axis(yaw, "horizontal"),
            "vertical": self._analyze_single_axis(pitch, "vertical"),
        }
        
        # 生成总结
        h_present = results["horizontal"]["present"]
        v_present = results["vertical"]["present"]
        
        if not h_present and not v_present:
            summary = "未检测到明显眼震"
        elif h_present and not v_present:
            h_dir = results["horizontal"]["direction_label"]
            summary = f"检测到水平眼震，快相方向: {h_dir}"
        elif v_present and not h_present:
            v_dir = results["vertical"]["direction_label"]
            summary = f"检测到垂直眼震，快相方向: {v_dir}"
        else:
            h_dir = results["horizontal"]["direction_label"]
            v_dir = results["vertical"]["direction_label"]
            summary = f"检测到混合眼震 - 水平({h_dir}) + 垂直({v_dir})"
        
        results["summary"] = summary
        return results
    
    def _analyze_single_axis(self, angles: np.ndarray, axis: str) -> Dict[str, Any]:
        """分析单轴眼震"""
        velocity = self.compute_velocity(angles)
        amplitude = np.percentile(angles, 95) - np.percentile(angles, 5)
        direction_info = self.analyze_direction(angles, velocity)
        freq_info = self.compute_frequency(angles)
        
        has_sufficient_amplitude = amplitude > self.min_amplitude
        has_rhythmic_pattern = freq_info["dominant_freq"] > self.min_frequency
        has_fast_phases = direction_info["confidence"] > 0.3
        
        present = has_sufficient_amplitude and (has_rhythmic_pattern or has_fast_phases)
        
        # 方向标签
        if axis == "horizontal":
            if direction_info["direction"] == "正向":
                direction_label = "向右"
            elif direction_info["direction"] == "负向":
                direction_label = "向左"
            else:
                direction_label = direction_info["direction"]
        else:  # vertical
            if direction_info["direction"] == "正向":
                direction_label = "向上"
            elif direction_info["direction"] == "负向":
                direction_label = "向下"
            else:
                direction_label = direction_info["direction"]
        
        return {
            "present": present,
            "direction": direction_info["direction"],
            "direction_label": direction_label,
            "amplitude": float(amplitude),
            "frequency": float(freq_info["dominant_freq"]),
            "confidence": float(direction_info["confidence"]),
        }


# ==============================================================================
#  完整版眼震分析器 (用于详细分析和可视化)
# ==============================================================================
class NystagmusAnalyzer:
    """
    完整版眼震分析器
    包含信号预处理、拐点检测、斜率计算、模式识别等
    
    适用场景:
    - 详细的眼震分析
    - 4步骤可视化
    - SPV (慢相速度) 计算
    - CV (变异系数) 分析
    """
    
    # 重采样后的目标采样率 (Hz) - 固定值，确保所有视频处理一致
    # 设计基于 60 Hz 原始采样率 × 10 倍插值 = 600 Hz
    TARGET_SAMPLE_RATE = 600.0
    
    def __init__(self, fps: float = 30.0):
        self.fps = fps
        self.resampled_fps = self.TARGET_SAMPLE_RATE  # 重采样后的采样率
        
    def butter_highpass_filter(self, data: np.ndarray, cutoff: float, fs: float, order: int = 5) -> np.ndarray:
        """零相位高通Butterworth滤波器"""
        nyquist = 0.5 * fs
        normal_cutoff = cutoff / nyquist
        if normal_cutoff >= 1:
            return data
        b, a = scipy.signal.butter(order, normal_cutoff, btype='high', analog=False)
        filtered_data = scipy.signal.filtfilt(b, a, data, 
                                              padlen=min(len(data)-1, 3*(max(len(b), len(a))-1)))
        return filtered_data
    
    def butter_lowpass_filter(self, data: np.ndarray, cutoff: float, fs: float, order: int = 5) -> np.ndarray:
        """零相位低通Butterworth滤波器"""
        nyquist = 0.5 * fs
        normal_cutoff = cutoff / nyquist
        if normal_cutoff >= 1:
            return data
        b, a = scipy.signal.butter(order, normal_cutoff, btype='low', analog=False)
        filtered_data = scipy.signal.filtfilt(b, a, data, 
                                              padlen=min(len(data)-1, 3*(max(len(b), len(a))-1)))
        return filtered_data
    
    def moving_average_filter(self, data: np.ndarray, window_size: int) -> np.ndarray:
        """移动平均滤波器"""
        window_size = int(window_size)
        half_window = window_size // 2
        padded_data = np.pad(data, (half_window, half_window), mode='edge')
        ma = np.cumsum(padded_data, dtype=float)
        ma[window_size:] = ma[window_size:] - ma[:-window_size]
        filtered_data = ma[window_size - 1:] / window_size
        return filtered_data[:len(data)]
    
    def signal_preprocess(self, timestamps: np.ndarray, eye_angles: np.ndarray, 
                         highpass_cutoff: float = 0.1, lowpass_cutoff: float = 6.0) -> Tuple[np.ndarray, np.ndarray]:
        """
        信号预处理：滤波和重采样
        
        重采样到固定的 TARGET_SAMPLE_RATE (300 Hz)，确保后续处理参数一致
        
        Args:
            timestamps: 时间戳数组
            eye_angles: 眼动角度数组
            highpass_cutoff: 高通滤波截止频率
            lowpass_cutoff: 低通滤波截止频率
            
        Returns:
            (filtered_signal, time): 预处理后的信号和时间
        """
        original_time = timestamps
        original_signal = eye_angles
        
        min_len = min(len(original_time), len(original_signal))
        original_time = original_time[:min_len]
        original_signal = original_signal[:min_len]
        
        if len(original_signal) == 0 or len(original_time) == 0:
            return np.array([]), np.array([])
        
        # 1. 高通滤波 (去除低频漂移)
        signal_filtered = self.butter_highpass_filter(
            original_signal, cutoff=highpass_cutoff, fs=self.fps, order=5
        )
        
        # 2. 低通滤波 (去除高频噪声)
        signal_filtered = self.butter_lowpass_filter(
            signal_filtered, cutoff=lowpass_cutoff, fs=self.fps, order=5
        )
        
        # 3. 重采样到固定的目标采样率 (300 Hz)
        # 根据信号时长和目标采样率计算目标样本数
        duration = original_time[-1] - original_time[0]
        target_samples = int(duration * self.TARGET_SAMPLE_RATE)
        target_samples = max(target_samples, len(original_signal))  # 至少保持原样本数
        
        signal_filtered = scipy.signal.resample(signal_filtered, target_samples)
        
        # 4. 生成新的时间序列
        time = np.linspace(original_time[0], original_time[-1], len(signal_filtered))
        
        return signal_filtered, time
    
    def find_turning_points(self, signal_data: np.ndarray, 
                            prominence: float = 0.2, 
                            min_distance_sec: float = 0.25) -> np.ndarray:
        """
        检测拐点（局部极大值和极小值）
        
        Args:
            signal_data: 信号数据
            prominence: 峰值突出度阈值 (度)
            min_distance_sec: 相邻拐点最小时间间隔 (秒)，默认0.25秒
            
        Returns:
            turning_points: 拐点索引数组
        """
        # 根据重采样后的采样率计算样本距离
        # TARGET_SAMPLE_RATE = 600 Hz, min_distance_sec = 0.25s → distance = 150 samples
        distance = int(min_distance_sec * self.resampled_fps)
        distance = max(1, distance)  # 至少1个样本
        
        peaks, _ = scipy.signal.find_peaks(signal_data, prominence=prominence, distance=distance)
        valleys, _ = scipy.signal.find_peaks(-signal_data, prominence=prominence, distance=distance)
        turning_points = np.sort(np.concatenate([peaks, valleys]))
        return turning_points
    
    def calculate_slopes(self, time: np.ndarray, signal: np.ndarray, turning_points: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
        """
        计算相邻拐点之间的斜率
        
        Returns:
            (slope_times, slopes): 斜率时间点和斜率值
        """
        slopes = []
        slope_times = []
        for i in range(len(turning_points)-1):
            t1, t2 = time[turning_points[i]], time[turning_points[i+1]]
            y1, y2 = signal[turning_points[i]], signal[turning_points[i+1]]
            slope = (y2 - y1) / (t2 - t1)
            slope_time = (t1 + t2) / 2
            slopes.append(slope)
            slope_times.append(slope_time)
        return np.array(slope_times), np.array(slopes)
    
    def identify_nystagmus_patterns(self, signal_data: np.ndarray, time_data: np.ndarray, 
                                    min_time: float = 0.15, max_time: float = 1.5,
                                    min_ratio: float = 1.2, max_ratio: float = 10.0, 
                                    min_amplitude: float = 5.0,
                                    direction_axis: str = "horizontal") -> Tuple[List, List, str, float, float, bool]:
        """
        识别眼震模式（快相和慢相）
        
        Args:
            signal_data: 信号数据
            time_data: 时间数据
            min_time: 最小模式持续时间
            max_time: 最大模式持续时间
            min_ratio: 最小快慢相速度比 (默认1.2)
            max_ratio: 最大快慢相速度比 (默认10.0)
            min_amplitude: 最小幅度阈值 (度)，默认3°
            direction_axis: 方向轴 ("horizontal" 或 "vertical")
            
        Returns:
            patterns: 有效的眼震模式
            filtered_patterns: 被过滤的模式（离群值）
            direction: 眼震方向 (left/right/up/down)
            spv: 慢相速度 (deg/s)
            cv: 变异系数 (%)
        """
        # 检测拐点
        # prominence=0.2° 峰值突出度, min_distance_sec=0.25s 最小间隔 (600Hz下=150样本)
        turning_points = self.find_turning_points(signal_data, prominence=0.2, min_distance_sec=0.25)
        
        if len(turning_points) < 3:
            return [], [], "unknown", 0, float('inf'), False
        
        # 收集潜在的眼震模式
        potential_patterns = []
        
        for i in range(1, len(turning_points)-1):
            idx1 = turning_points[i-1]
            idx2 = turning_points[i]
            idx3 = turning_points[i+1]
            
            p1 = np.array([time_data[idx1], signal_data[idx1]])
            p2 = np.array([time_data[idx2], signal_data[idx2]])
            p3 = np.array([time_data[idx3], signal_data[idx3]])
            
            # ============================================================
            # 限制条件1: 只检测向上突的三角形 (峰值)
            # p2 必须高于两侧 (p1 和 p3)
            # ============================================================
            is_peak = (p2[1] > p1[1] and p2[1] > p3[1])
            
            if not is_peak:
                continue  # 不是峰值，跳过
            
            # ============================================================
            # 限制条件2: 幅度必须超过阈值 (默认5°)
            # 幅度定义为从谷到峰的距离，任意一侧达到阈值即可
            # ============================================================
            amplitude_left = abs(p2[1] - p1[1])
            amplitude_right = abs(p2[1] - p3[1])
            amplitude = max(amplitude_left, amplitude_right)
            
            if amplitude < min_amplitude:
                continue
            
            # 检查时间阈值
            total_time = p3[0] - p1[0]
            if not (min_time <= total_time <= max_time):
                continue
            
            # 计算斜率
            slope_before = (p2[1] - p1[1]) / (p2[0] - p1[0])
            slope_after = (p3[1] - p2[1]) / (p3[0] - p2[0])
            
            # 确定快相/慢相 (绝对值大的是快相)
            if abs(slope_before) > abs(slope_after):
                fast_slope = slope_before
                slow_slope = slope_after
                fast_phase_first = True
            else:
                fast_slope = slope_after
                slow_slope = slope_before
                fast_phase_first = False
            
            # 快相和慢相方向应该相反 (一个正一个负)
            if fast_slope * slow_slope > 0:
                continue
            
            ratio = abs(fast_slope) / abs(slow_slope) if slow_slope != 0 else float('inf')
            
            if min_ratio <= ratio <= max_ratio:
                potential_patterns.append({
                    'index': i,
                    'time_point': time_data[idx2],
                    'peak_value': p2[1],
                    'amplitude': amplitude,
                    'amplitude_left': amplitude_left,
                    'amplitude_right': amplitude_right,
                    'slow_slope': slow_slope,
                    'fast_slope': fast_slope,
                    'ratio': ratio,
                    'fast_phase_first': fast_phase_first,
                    'total_time': total_time
                })
        
        if not potential_patterns:
            return [], [], "unknown", 0, float('inf'), False
        
        # ============================================================
        # 按慢相方向分组 (正向 vs 负向)
        # 眼震方向以快相定义，但分组用慢相方向
        # ============================================================
        positive_patterns = []  # slow_slope > 0
        negative_patterns = []  # slow_slope < 0
        
        for i, p in enumerate(potential_patterns):
            p['original_index'] = i  # 记录原始索引用于连续性检测
            if p['slow_slope'] > 0:
                positive_patterns.append(p)
            else:
                negative_patterns.append(p)
        
        # ============================================================
        # 对每个方向检查连续性 (必须连续3个才算有效)
        # 注意：需要在所有pattern中检查，看是否有连续3个同方向的
        # ============================================================
        pos_has_consecutive = self._check_consecutive_patterns_in_group(potential_patterns, "positive", min_consecutive=3)
        neg_has_consecutive = self._check_consecutive_patterns_in_group(potential_patterns, "negative", min_consecutive=3)
        
        # ============================================================
        # 根据连续性确定有效方向和计算CV
        # ============================================================
        valid_patterns = []
        filtered_patterns = []
        direction = "unknown"
        spv = 0
        cv = float('inf')
        has_nystagmus = False
        
        if pos_has_consecutive and neg_has_consecutive:
            # 双向眼震：两个方向都有连续3个
            direction = "bidirectional"
            valid_patterns = potential_patterns  # 保留所有
            
            # 分别计算两个方向的 SPV，取较大值
            pos_slopes = np.array([p['slow_slope'] for p in positive_patterns])
            neg_slopes = np.array([abs(p['slow_slope']) for p in negative_patterns])
            spv = max(np.median(pos_slopes), np.median(neg_slopes))
            
            # CV 分别计算，取较大值
            cv_pos = self._compute_cv(pos_slopes)
            cv_neg = self._compute_cv(neg_slopes)
            cv = max(cv_pos, cv_neg)
            has_nystagmus = True
            
        elif pos_has_consecutive:
            # 只有正向有连续3个
            valid_patterns = positive_patterns
            filtered_patterns = negative_patterns  # 负向的都算过滤掉
            
            slopes = np.array([p['slow_slope'] for p in positive_patterns])
            spv = abs(np.median(slopes))
            cv = self._compute_cv(slopes)
            
            if direction_axis == "horizontal":
                direction = "left"  # 慢相正向 = 快相向左
            else:
                direction = "up"
            has_nystagmus = True
            
        elif neg_has_consecutive:
            # 只有负向有连续3个
            valid_patterns = negative_patterns
            filtered_patterns = positive_patterns  # 正向的都算过滤掉
            
            slopes = np.array([abs(p['slow_slope']) for p in negative_patterns])
            spv = np.median(slopes)
            cv = self._compute_cv(slopes)
            
            if direction_axis == "horizontal":
                direction = "right"  # 慢相负向 = 快相向右
            else:
                direction = "down"
            has_nystagmus = True
            
        else:
            # 两个方向都没有连续3个 → 无眼震
            filtered_patterns = potential_patterns
            direction = "none"
            has_nystagmus = False
        
        return valid_patterns, filtered_patterns, direction, spv, cv, has_nystagmus
    
    def _compute_cv(self, slopes: np.ndarray) -> float:
        """计算变异系数 (CV) - 使用 MAD 方法"""
        if len(slopes) < 2:
            return float('inf')
        median_slope = np.median(slopes)
        mad = np.median(np.abs(slopes - median_slope))
        mad_normalized = 1.4826 * mad
        cv = (mad_normalized / abs(median_slope)) * 100 if median_slope != 0 else float('inf')
        return cv
    
    def _check_consecutive_patterns_in_group(self, all_patterns: List[Dict], 
                                              target_direction: str,
                                              min_consecutive: int = 3,
                                              max_gap: float = 0.1) -> bool:
        """
        检查同方向的pattern中，是否有连续min_consecutive个时间上接近的pattern
        
        Args:
            all_patterns: 所有pattern
            target_direction: 目标方向 ("positive" 或 "negative")
            min_consecutive: 最少连续数量 (默认3)
            max_gap: 相邻pattern之间最大时间间隔 (秒)，默认0.1s
            
        Returns:
            bool: 是否存在足够数量的连续同方向pattern
        """
        # 筛选出目标方向的pattern
        if target_direction == "positive":
            target_patterns = [p for p in all_patterns if p['slow_slope'] > 0]
        else:
            target_patterns = [p for p in all_patterns if p['slow_slope'] < 0]
        
        if len(target_patterns) < min_consecutive:
            return False
        
        # 按时间排序
        sorted_patterns = sorted(target_patterns, key=lambda p: p['time_point'])
        
        consecutive_count = 1
        max_consecutive = 1
        
        for i in range(1, len(sorted_patterns)):
            # 计算当前pattern开始时间与上一个pattern结束时间的间隔
            # pattern 持续时间是 total_time，time_point 是峰值时间点
            prev_end = sorted_patterns[i-1]['time_point'] + sorted_patterns[i-1]['total_time'] / 2
            curr_start = sorted_patterns[i]['time_point'] - sorted_patterns[i]['total_time'] / 2
            gap = curr_start - prev_end
            
            if gap <= max_gap:
                consecutive_count += 1
                max_consecutive = max(max_consecutive, consecutive_count)
            else:
                # 间隔太大，重置计数
                consecutive_count = 1
        
        return max_consecutive >= min_consecutive
    
    def analyze(self, timestamps: np.ndarray, angles: np.ndarray, blink_mask: np.ndarray, 
                axis: str = "horizontal") -> Dict[str, Any]:
        """
        完整的眼震分析流程
        
        Args:
            timestamps: 时间数组
            angles: 角度数组 (Pitch 或 Yaw)
            blink_mask: 眨眼掩码，True表示眨眼（需排除）
            axis: "horizontal" (yaw) 或 "vertical" (pitch)
        
        Returns:
            包含所有分析结果的字典，用于可视化和报告
        """
        # 排除眨眼数据
        valid_mask = ~blink_mask
        valid_times = timestamps[valid_mask]
        valid_angles = angles[valid_mask]
        
        if len(valid_times) < 30:
            return {
                'success': False,
                'error': 'Not enough valid data (too many blinks)',
                'n_valid_samples': len(valid_times)
            }
        
        # 存储原始数据用于可视化
        original_times = valid_times.copy()
        original_angles = valid_angles.copy()
        
        # Step 1: 仅高通滤波
        signal_highpass = self.butter_highpass_filter(
            valid_angles, cutoff=0.1, fs=self.fps, order=5
        )
        
        # Step 2: 低通滤波（基于高通输出）
        signal_lowpass = self.butter_lowpass_filter(
            signal_highpass, cutoff=6.0, fs=self.fps, order=5
        )
        
        # Step 3: 完整预处理（包含重采样到 300 Hz）
        filtered_signal, time = self.signal_preprocess(
            valid_times, valid_angles,
            highpass_cutoff=0.1, lowpass_cutoff=6.0
        )
        
        if len(filtered_signal) == 0:
            return {
                'success': False,
                'error': 'Signal preprocessing failed'
            }
        
        # 检测拐点
        turning_points = self.find_turning_points(filtered_signal, prominence=0.2, min_distance_sec=0.25)
        
        # 计算斜率
        slope_times, slopes = self.calculate_slopes(time, filtered_signal, turning_points)
        
        # 识别眼震模式
        patterns, filtered_patterns, direction, spv, cv, has_nystagmus = self.identify_nystagmus_patterns(
            filtered_signal, time,
            min_time=0.15, max_time=1.5,   # 时间范围: 0.15-1.5秒
            min_ratio=1.2, max_ratio=10.0,  # 速度比: 1.2-10.0
            min_amplitude=5.0,  # 幅度阈值: 5°
            direction_axis=axis
        )
        
        return {
            'success': True,
            'axis': axis,
            'n_valid_samples': len(valid_times),
            'n_blink_samples': np.sum(blink_mask),
            # 原始数据用于绘图
            'original_times': original_times,
            'original_angles': original_angles,
            # 中间处理步骤
            'signal_highpass': signal_highpass,
            'signal_lowpass': signal_lowpass,
            # 最终处理数据
            'filtered_signal': filtered_signal,
            'time': time,
            'turning_points': turning_points,
            'slope_times': slope_times,
            'slopes': slopes,
            'patterns': patterns,
            'filtered_patterns': filtered_patterns,
            'n_patterns': len(patterns),
            'n_filtered_patterns': len(filtered_patterns),
            'direction': direction,
            'spv': spv,
            'cv': cv,
            # 核心判断：是否存在眼震 (需要连续3个以上模式)
            'has_nystagmus': has_nystagmus,
        }


# ==============================================================================
#  拐点检测器 (独立使用)
# ==============================================================================
class InflectionPointDetector:
    """
    检测角度曲线的拐点
    可独立于眼震分析使用
    """
    
    def __init__(self, min_prominence: float = 1.0, min_distance_sec: float = 0.1):
        """
        Args:
            min_prominence: 最小峰值突出度
            min_distance_sec: 相邻拐点最小时间间隔(秒)
        """
        self.min_prominence = min_prominence
        self.min_distance_sec = min_distance_sec
    
    def detect(self, angles: np.ndarray, fps: float) -> Dict[str, np.ndarray]:
        """
        检测拐点（局部极值点）
        
        Args:
            angles: 角度数组
            fps: 帧率
            
        Returns:
            {
                "peaks": np.ndarray,    # 峰值索引
                "valleys": np.ndarray,  # 谷值索引
            }
        """
        min_distance = int(self.min_distance_sec * fps)
        min_distance = max(1, min_distance)
        
        # 检测峰值
        peaks, _ = scipy.signal.find_peaks(
            angles, 
            prominence=self.min_prominence,
            distance=min_distance
        )
        
        # 检测谷值
        valleys, _ = scipy.signal.find_peaks(
            -angles, 
            prominence=self.min_prominence,
            distance=min_distance
        )
        
        return {"peaks": peaks, "valleys": valleys}


# ==============================================================================
#  便捷函数
# ==============================================================================
def quick_nystagmus_check(pitch: np.ndarray, yaw: np.ndarray, fps: float = 30.0) -> Dict[str, Any]:
    """
    快速眼震检测便捷函数
    
    Args:
        pitch: 俯仰角数组
        yaw: 偏航角数组
        fps: 帧率
        
    Returns:
        检测结果字典
    """
    detector = NystagmusDetector(fps=fps)
    return detector.detect(pitch, yaw)


def full_nystagmus_analysis(timestamps: np.ndarray, angles: np.ndarray, 
                            blink_mask: np.ndarray, axis: str = "horizontal",
                            fps: float = 30.0) -> Dict[str, Any]:
    """
    完整眼震分析便捷函数
    
    Args:
        timestamps: 时间戳数组
        angles: 角度数组
        blink_mask: 眨眼掩码
        axis: 分析轴向
        fps: 帧率
        
    Returns:
        分析结果字典
    """
    analyzer = NystagmusAnalyzer(fps=fps)
    return analyzer.analyze(timestamps, angles, blink_mask, axis)

