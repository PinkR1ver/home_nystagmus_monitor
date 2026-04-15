"""
图像预处理模块，用于处理不同采集标准的眼图数据。

解决不同相机、分辨率、光照条件导致的图像分布差异问题。
同时处理距离和位置不固定的问题（通过几何归一化）。
"""

import numpy as np
import torch
import torch.nn.functional as F
from torchvision import transforms
import cv2
from geometric_normalization import RobustGeometricNormalizer


class EyeImagePreprocessor:
    """
    眼图预处理器，用于标准化不同采集条件的图像。
    
    主要功能：
    1. 尺寸归一化：将不同尺寸的图像统一到目标尺寸
    2. 光照归一化：减少光照条件差异的影响
    3. 对比度归一化：标准化图像对比度
    4. 颜色归一化：处理不同色彩空间/相机参数
    5. 几何归一化：基于关键点的几何归一化（如果可用）
    """
    
    def __init__(self, 
                 target_size=(36, 60),
                 normalize_illumination=True,
                 normalize_contrast=True,
                 normalize_color=True,
                 gamma_correction=True,
                 adaptive_hist_eq=True,
                 use_geometric_normalization=False,
                 geometric_normalizer=None):
        """
        Args:
            target_size: 目标图像尺寸 (height, width)
            normalize_illumination: 是否进行光照归一化
            normalize_contrast: 是否进行对比度归一化
            normalize_color: 是否进行颜色归一化
            gamma_correction: 是否进行gamma校正
            adaptive_hist_eq: 是否使用自适应直方图均衡化
            use_geometric_normalization: 是否使用几何归一化（处理距离和位置变化）
            geometric_normalizer: 几何归一化器实例，如果为None且use_geometric_normalization=True，则创建默认的
        """
        self.target_size = target_size
        self.normalize_illumination = normalize_illumination
        self.normalize_contrast = normalize_contrast
        self.normalize_color = normalize_color
        self.gamma_correction = gamma_correction
        self.adaptive_hist_eq = adaptive_hist_eq
        self.use_geometric_normalization = use_geometric_normalization
        
        # 创建几何归一化器（如果需要）
        if use_geometric_normalization:
            if geometric_normalizer is None:
                self.geometric_normalizer = RobustGeometricNormalizer(
                    target_size=target_size,
                    fallback_to_center=True,
                    use_pupil=True
                )
            else:
                self.geometric_normalizer = geometric_normalizer
        else:
            self.geometric_normalizer = None
    
    def __call__(self, image, keypoints=None, eye_bbox=None):
        """
        处理单个图像。
        
        Args:
            image: 输入图像，可以是numpy array或torch tensor
                  - numpy: shape (H, W) 或 (H, W, C) 或 (C, H, W)
                  - torch: shape (C, H, W) 或 (H, W)
            keypoints: 可选的关键点坐标，用于几何归一化 (6, 2) 或 (4, 2)
            eye_bbox: 可选的眼睛边界框，用于几何归一化 [x, y, width, height]
        
        Returns:
            处理后的图像，torch tensor, shape (C, H, W), dtype float32, range [0, 1]
        """
        # 转换为numpy array处理
        if isinstance(image, torch.Tensor):
            image_np = image.detach().cpu().numpy()
            is_torch = True
        else:
            image_np = np.array(image)
            is_torch = False
        
        # 处理不同的输入格式
        if image_np.ndim == 2:
            # (H, W) -> (H, W, 1)
            image_np = image_np[..., np.newaxis]
        elif image_np.ndim == 3 and image_np.shape[0] < image_np.shape[2]:
            # (C, H, W) -> (H, W, C)
            image_np = image_np.transpose(1, 2, 0)
        
        # 确保是uint8格式，范围[0, 255]
        if image_np.dtype != np.uint8:
            if image_np.max() <= 1.0:
                image_np = (image_np * 255).astype(np.uint8)
            else:
                image_np = np.clip(image_np, 0, 255).astype(np.uint8)
        
        H, W, C = image_np.shape
        
        # 1. 几何归一化（如果启用，优先于简单尺寸归一化）
        if self.use_geometric_normalization and self.geometric_normalizer is not None:
            # 使用几何归一化处理距离和位置变化
            image_np = self.geometric_normalizer.normalize(image_np, keypoints=keypoints, eye_bbox=eye_bbox)
            H, W, C = image_np.shape
        else:
            # 1. 简单的尺寸归一化
            if (H, W) != self.target_size:
                image_np = cv2.resize(image_np, (self.target_size[1], self.target_size[0]), 
                                     interpolation=cv2.INTER_AREA)
        
        # 2. 转换为RGB（如果是灰度图）
        if C == 1:
            image_np = cv2.cvtColor(image_np, cv2.COLOR_GRAY2RGB)
        elif C == 3:
            # 确保是RGB格式（OpenCV默认是BGR）
            image_np = cv2.cvtColor(image_np, cv2.COLOR_BGR2RGB)
        elif C == 4:
            image_np = cv2.cvtColor(image_np, cv2.COLOR_BGRA2RGB)
        
        # 3. 光照归一化
        if self.normalize_illumination:
            image_np = self._normalize_illumination(image_np)
        
        # 4. 对比度归一化
        if self.normalize_contrast:
            image_np = self._normalize_contrast(image_np)
        
        # 5. 自适应直方图均衡化（可选，可能对某些图像过度增强）
        if self.adaptive_hist_eq:
            image_np = self._adaptive_histogram_equalization(image_np)
        
        # 6. 颜色归一化
        if self.normalize_color:
            image_np = self._normalize_color(image_np)
        
        # 7. Gamma校正
        if self.gamma_correction:
            image_np = self._gamma_correction(image_np, gamma=1.2)
        
        # 转换为 (C, H, W) 格式
        if image_np.ndim == 3:
            image_np = image_np.transpose(2, 0, 1)  # (H, W, C) -> (C, H, W)
        
        # 归一化到[0, 1]
        image_np = image_np.astype(np.float32) / 255.0
        
        # 转换为torch tensor
        image_tensor = torch.from_numpy(image_np).float()
        
        return image_tensor
    
    def _normalize_illumination(self, image):
        """光照归一化：去除不均匀光照的影响"""
        # 转换为LAB颜色空间进行光照归一化
        lab = cv2.cvtColor(image, cv2.COLOR_RGB2LAB)
        l_channel = lab[:, :, 0]
        
        # 使用高斯模糊估计光照
        blur = cv2.GaussianBlur(l_channel, (15, 15), 0)
        l_normalized = cv2.addWeighted(l_channel, 1.5, blur, -0.5, 0)
        
        # 限制范围
        l_normalized = np.clip(l_normalized, 0, 255)
        lab[:, :, 0] = l_normalized
        
        # 转回RGB
        image = cv2.cvtColor(lab, cv2.COLOR_LAB2RGB)
        return image
    
    def _normalize_contrast(self, image):
        """对比度归一化：使用CLAHE (Contrast Limited Adaptive Histogram Equalization)"""
        # 转换到LAB颜色空间，只对L通道做CLAHE
        lab = cv2.cvtColor(image, cv2.COLOR_RGB2LAB)
        l_channel = lab[:, :, 0]
        
        # 应用CLAHE
        clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
        l_channel = clahe.apply(l_channel)
        lab[:, :, 0] = l_channel
        
        # 转回RGB
        image = cv2.cvtColor(lab, cv2.COLOR_LAB2RGB)
        return image
    
    def _adaptive_histogram_equalization(self, image):
        """自适应直方图均衡化（可选）"""
        # 转换到YCbCr颜色空间
        ycbcr = cv2.cvtColor(image, cv2.COLOR_RGB2YCrCb)
        y_channel = ycbcr[:, :, 0]
        
        # 自适应直方图均衡化
        clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8))
        y_channel = clahe.apply(y_channel)
        ycbcr[:, :, 0] = y_channel
        
        # 转回RGB
        image = cv2.cvtColor(ycbcr, cv2.COLOR_YCrCb2RGB)
        return image
    
    def _normalize_color(self, image):
        """颜色归一化：标准化颜色分布"""
        # 将每个通道归一化到[0, 255]
        for c in range(3):
            channel = image[:, :, c]
            # 使用均值方差归一化
            mean = channel.mean()
            std = channel.std() + 1e-8
            channel = (channel - mean) / std
            # 映射回[0, 255]
            channel = ((channel - channel.min()) / (channel.max() - channel.min() + 1e-8)) * 255
            image[:, :, c] = np.clip(channel, 0, 255)
        return image
    
    def _gamma_correction(self, image, gamma=1.2):
        """Gamma校正：调整图像亮度"""
        inv_gamma = 1.0 / gamma
        table = np.array([((i / 255.0) ** inv_gamma) * 255 for i in np.arange(0, 256)]).astype("uint8")
        image = cv2.LUT(image, table)
        return image


class SimplePreprocessor:
    """
    简单预处理器：仅做基本的尺寸归一化和数值归一化。
    适用于MPIIGaze等已经预处理过的数据集。
    """
    
    def __init__(self, target_size=(36, 60)):
        self.target_size = target_size
    
    def __call__(self, image):
        """
        简单预处理：尺寸调整和归一化。
        
        Args:
            image: 输入图像，numpy array 或 torch tensor
        
        Returns:
            处理后的图像，torch tensor, shape (C, H, W)
        """
        if isinstance(image, torch.Tensor):
            image_np = image.detach().cpu().numpy()
        else:
            image_np = np.array(image)
        
        # 处理格式
        if image_np.ndim == 2:
            image_np = image_np[np.newaxis, ...]  # (H, W) -> (1, H, W)
        elif image_np.ndim == 3:
            if image_np.shape[2] < image_np.shape[0]:
                # (C, H, W)
                pass
            else:
                # (H, W, C) -> (C, H, W)
                image_np = image_np.transpose(2, 0, 1)
        
        C, H, W = image_np.shape
        
        # 尺寸调整
        if (H, W) != self.target_size:
            image_np = np.stack([
                cv2.resize(image_np[c], (self.target_size[1], self.target_size[0]), 
                          interpolation=cv2.INTER_AREA)
                for c in range(C)
            ], axis=0)
        
        # 灰度图转RGB
        if C == 1:
            image_np = np.repeat(image_np, 3, axis=0)
        
        # 归一化到[0, 1]
        if image_np.max() > 1.0:
            image_np = image_np.astype(np.float32) / 255.0
        
        return torch.from_numpy(image_np).float()


def get_preprocessor(config):
    """
    根据配置创建预处理器。
    
    Args:
        config: 配置字典，包含preprocessing相关参数
    
    Returns:
        Preprocessor实例
    """
    preproc_config = config.get('preprocessing', {})
    
    if preproc_config.get('mode', 'simple') == 'simple':
        return SimplePreprocessor(
            target_size=tuple(config['model']['img_size'])
        )
    else:
        return EyeImagePreprocessor(
            target_size=tuple(config['model']['img_size']),
            normalize_illumination=preproc_config.get('normalize_illumination', True),
            normalize_contrast=preproc_config.get('normalize_contrast', True),
            normalize_color=preproc_config.get('normalize_color', True),
            gamma_correction=preproc_config.get('gamma_correction', True),
            adaptive_hist_eq=preproc_config.get('adaptive_hist_eq', False),
            use_geometric_normalization=preproc_config.get('use_geometric_normalization', False)
        )


if __name__ == "__main__":
    # 测试预处理器
    print("Testing Image Preprocessors...")
    
    # 创建测试图像（模拟不同采集条件）
    test_images = [
        np.random.randint(0, 255, (40, 70, 3), dtype=np.uint8),  # 不同尺寸
        np.random.randint(0, 255, (30, 50, 3), dtype=np.uint8),  # 不同尺寸
        np.random.randint(0, 255, (36, 60), dtype=np.uint8),     # 灰度图
    ]
    
    # 测试简单预处理器
    print("\n1. Testing SimplePreprocessor...")
    simple_preproc = SimplePreprocessor(target_size=(36, 60))
    for i, img in enumerate(test_images):
        processed = simple_preproc(img)
        print(f"  Image {i+1}: {img.shape} -> {processed.shape}, range: [{processed.min():.2f}, {processed.max():.2f}]")
    
    # 测试完整预处理器
    print("\n2. Testing EyeImagePreprocessor...")
    full_preproc = EyeImagePreprocessor(
        target_size=(36, 60),
        normalize_illumination=True,
        normalize_contrast=True,
        normalize_color=True,
        gamma_correction=True,
        adaptive_hist_eq=False
    )
    for i, img in enumerate(test_images):
        processed = full_preproc(img)
        print(f"  Image {i+1}: {img.shape} -> {processed.shape}, range: [{processed.min():.2f}, {processed.max():.2f}]")
    
    print("\nPreprocessor tests completed!")
