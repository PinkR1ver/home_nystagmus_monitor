"""
几何归一化模块：基于关键点的几何归一化

解决人眼到摄像头距离不同和位置不固定的问题。
使用眼部关键点（眼角、瞳孔）进行仿射变换，将眼睛归一化到标准位置和大小。
"""

import numpy as np
import cv2
import torch


class GeometricNormalizer:
    """
    基于关键点的几何归一化器。
    
    使用眼部关键点（眼角、瞳孔）计算仿射变换矩阵，
    将眼睛区域归一化到标准位置和大小，消除距离和位置变化的影响。
    """
    
    def __init__(self, 
                 target_size=(36, 60),
                 reference_points=None,
                 eye_scale=1.0,
                 use_pupil=True):
        """
        Args:
            target_size: 目标输出图像尺寸 (height, width)
            reference_points: 参考关键点坐标（归一化后眼睛的标准位置）
                             如果为None，使用默认值
            eye_scale: 眼睛区域相对于图像的比例（用于确定裁剪区域）
            use_pupil: 是否使用瞳孔位置进行更精确的归一化
        """
        self.target_size = target_size
        self.eye_scale = eye_scale
        self.use_pupil = use_pupil
        
        # 默认参考点（归一化后的标准位置）
        # 格式: [[左外眼角], [左内眼角], [右内眼角], [右外眼角], [左瞳孔], [右瞳孔]]
        if reference_points is None:
            # 假设眼睛中心在图像中心，眼间距约为图像宽度的60%
            eye_width = target_size[1] * 0.6
            eye_height = target_size[0] * 0.3
            center_x = target_size[1] / 2
            center_y = target_size[0] / 2
            
            self.reference_points = np.array([
                [center_x - eye_width/2, center_y],  # 左外眼角
                [center_x - eye_width/4, center_y],  # 左内眼角
                [center_x + eye_width/4, center_y],  # 右内眼角
                [center_x + eye_width/2, center_y],  # 右外眼角
                [center_x - eye_width/3, center_y],  # 左瞳孔（估计）
                [center_x + eye_width/3, center_y],  # 右瞳孔（估计）
            ], dtype=np.float32)
        else:
            self.reference_points = np.array(reference_points, dtype=np.float32)
    
    def normalize(self, image, keypoints=None, eye_bbox=None):
        """
        对图像进行几何归一化。
        
        Args:
            image: 输入图像，numpy array, shape (H, W, C) 或 (H, W)
            keypoints: 关键点坐标，shape (6, 2) 或 (4, 2)
                      格式: [左外眼角, 左内眼角, 右内眼角, 右外眼角, 左瞳孔, 右瞳孔]
                      如果没有瞳孔信息，可以只提供4个眼角点
            eye_bbox: 眼睛边界框 [x, y, width, height]，如果提供了bbox但没有keypoints，使用bbox估算
        
        Returns:
            归一化后的图像，numpy array, shape (target_height, target_width, C)
        """
        if isinstance(image, torch.Tensor):
            image = image.detach().cpu().numpy()
        
        # 处理输入格式
        if image.ndim == 2:
            image = image[..., np.newaxis]
        elif image.ndim == 3 and image.shape[0] < image.shape[2]:
            image = image.transpose(1, 2, 0)
        
        H, W = image.shape[:2]
        
        # 如果没有提供关键点，尝试从bbox估算或使用默认值
        if keypoints is None:
            if eye_bbox is not None:
                # 从bbox估算关键点
                x, y, w, h = eye_bbox
                keypoints = np.array([
                    [x, y + h/2],           # 左外眼角
                    [x + w/3, y + h/2],     # 左内眼角
                    [x + 2*w/3, y + h/2],   # 右内眼角
                    [x + w, y + h/2],       # 右外眼角
                    [x + w/4, y + h/2],     # 左瞳孔
                    [x + 3*w/4, y + h/2],   # 右瞳孔
                ], dtype=np.float32)
            else:
                # 使用图像中心区域作为默认
                center_x, center_y = W / 2, H / 2
                eye_width = min(W, H) * 0.6
                keypoints = np.array([
                    [center_x - eye_width/2, center_y],
                    [center_x - eye_width/4, center_y],
                    [center_x + eye_width/4, center_y],
                    [center_x + eye_width/2, center_y],
                    [center_x - eye_width/3, center_y],
                    [center_x + eye_width/3, center_y],
                ], dtype=np.float32)
        
        keypoints = np.array(keypoints, dtype=np.float32)
        
        # 如果只有4个点（眼角），添加估计的瞳孔位置
        if keypoints.shape[0] == 4:
            left_eye_center = (keypoints[0] + keypoints[1]) / 2
            right_eye_center = (keypoints[2] + keypoints[3]) / 2
            keypoints = np.vstack([
                keypoints,
                left_eye_center,
                right_eye_center
            ])
        
        # 选择用于计算变换矩阵的关键点
        if self.use_pupil and keypoints.shape[0] >= 6:
            # 使用眼角和瞳孔共6个点
            src_points = keypoints[:6]
            ref_points = self.reference_points[:6]
        else:
            # 只使用4个眼角点
            src_points = keypoints[:4]
            ref_points = self.reference_points[:4]
        
        # 计算仿射变换矩阵
        # 如果使用6个点，使用findHomography（透视变换）
        # 如果使用4个点，使用getAffineTransform（仿射变换）
        if len(src_points) >= 6:
            # 使用透视变换（更精确，但需要至少4个点）
            M, _ = cv2.findHomography(src_points[:4], ref_points[:4], cv2.RANSAC)
            if M is None:
                # 如果计算失败，降级到仿射变换
                M = cv2.getAffineTransform(src_points[:3], ref_points[:3])
                use_affine = True
            else:
                use_affine = False
        else:
            # 使用仿射变换
            M = cv2.getAffineTransform(src_points[:3], ref_points[:3])
            use_affine = True
        
        # 应用变换
        if use_affine:
            # 仿射变换
            normalized = cv2.warpAffine(
                image, M, (self.target_size[1], self.target_size[0]),
                flags=cv2.INTER_LINEAR,
                borderMode=cv2.BORDER_REPLICATE
            )
        else:
            # 透视变换
            normalized = cv2.warpPerspective(
                image, M, (self.target_size[1], self.target_size[0]),
                flags=cv2.INTER_LINEAR,
                borderMode=cv2.BORDER_REPLICATE
            )
        
        return normalized
    
    def __call__(self, image, keypoints=None, eye_bbox=None):
        """调用normalize方法"""
        return self.normalize(image, keypoints, eye_bbox)


class RobustGeometricNormalizer:
    """
    鲁棒的几何归一化器：结合关键点和自动检测。
    
    如果有关键点，使用关键点进行精确归一化；
    如果没有关键点，使用简单的裁剪和缩放（基于图像中心或检测到的眼睛位置）。
    """
    
    def __init__(self, 
                 target_size=(36, 60),
                 fallback_to_center=True,
                 use_pupil=True):
        """
        Args:
            target_size: 目标输出图像尺寸 (height, width)
            fallback_to_center: 如果没有关键点，是否使用图像中心区域
            use_pupil: 是否使用瞳孔位置
        """
        self.target_size = target_size
        self.fallback_to_center = fallback_to_center
        self.geometric_normalizer = GeometricNormalizer(
            target_size=target_size,
            use_pupil=use_pupil
        )
    
    def normalize(self, image, keypoints=None, eye_bbox=None):
        """
        鲁棒的归一化：优先使用关键点，如果没有则使用备选方案。
        
        Args:
            image: 输入图像
            keypoints: 关键点坐标
            eye_bbox: 眼睛边界框
        
        Returns:
            归一化后的图像
        """
        # 如果有关键点或bbox，使用几何归一化
        if keypoints is not None or eye_bbox is not None:
            try:
                return self.geometric_normalizer.normalize(image, keypoints, eye_bbox)
            except Exception as e:
                print(f"Warning: Geometric normalization failed: {e}, using fallback")
                # 如果失败，使用备选方案
                pass
        
        # 备选方案：简单的裁剪和缩放
        if isinstance(image, torch.Tensor):
            image = image.detach().cpu().numpy()
        
        # 处理输入格式
        if image.ndim == 2:
            image = image[..., np.newaxis]
        elif image.ndim == 3 and image.shape[0] < image.shape[2]:
            image = image.transpose(1, 2, 0)
        
        H, W = image.shape[:2]
        
        if self.fallback_to_center:
            # 使用中心区域
            center_x, center_y = W // 2, H // 2
            crop_size = min(W, H) * 0.8  # 裁剪80%的区域
            x1 = max(0, int(center_x - crop_size / 2))
            y1 = max(0, int(center_y - crop_size / 2))
            x2 = min(W, int(center_x + crop_size / 2))
            y2 = min(H, int(center_y + crop_size / 2))
            
            cropped = image[y1:y2, x1:x2]
        else:
            cropped = image
        
        # 调整大小到目标尺寸
        normalized = cv2.resize(
            cropped, 
            (self.target_size[1], self.target_size[0]),
            interpolation=cv2.INTER_AREA
        )
        
        return normalized
    
    def __call__(self, image, keypoints=None, eye_bbox=None):
        """调用normalize方法"""
        return self.normalize(image, keypoints, eye_bbox)


def parse_mpiigaze_keypoints(annotation_line):
    """
    解析MPIIGaze标注文件中的关键点。
    
    Args:
        annotation_line: 标注文件中的一行
                        格式: "filename x1 y1 x2 y2 x3 y3 x4 y4 x5 y5 x6 y6"
    
    Returns:
        keypoints: numpy array, shape (6, 2)
    """
    parts = annotation_line.strip().split()
    if len(parts) < 13:
        return None
    
    coords = [float(x) for x in parts[1:13]]
    keypoints = np.array([
        [coords[0], coords[1]],  # 左外眼角
        [coords[2], coords[3]],  # 左内眼角
        [coords[4], coords[5]],  # 右内眼角
        [coords[6], coords[7]],  # 右外眼角
        [coords[8], coords[9]],  # 左瞳孔
        [coords[10], coords[11]],  # 右瞳孔
    ], dtype=np.float32)
    
    return keypoints


if __name__ == "__main__":
    # 测试几何归一化
    print("Testing Geometric Normalization...")
    
    # 创建测试图像（模拟不同距离和位置）
    test_images = {
        'close': np.random.randint(0, 255, (200, 300, 3), dtype=np.uint8),  # 近距离
        'far': np.random.randint(0, 255, (100, 150, 3), dtype=np.uint8),    # 远距离
        'offset': np.random.randint(0, 255, (180, 240, 3), dtype=np.uint8), # 位置偏移
    }
    
    # 创建归一化器
    normalizer = RobustGeometricNormalizer(target_size=(36, 60))
    
    # 模拟不同距离的关键点
    test_keypoints = {
        'close': np.array([
            [50, 100],   # 左外眼角
            [100, 100],  # 左内眼角
            [150, 100],  # 右内眼角
            [200, 100],  # 右外眼角
            [75, 100],   # 左瞳孔
            [175, 100],  # 右瞳孔
        ], dtype=np.float32),
        'far': np.array([
            [20, 50],    # 左外眼角（更小的间距）
            [40, 50],    # 左内眼角
            [60, 50],    # 右内眼角
            [80, 50],    # 右外眼角
            [30, 50],    # 左瞳孔
            [70, 50],    # 右瞳孔
        ], dtype=np.float32),
    }
    
    print("\n1. Testing with keypoints...")
    for name, img in test_images.items():
        if name in test_keypoints:
            normalized = normalizer(img, keypoints=test_keypoints[name])
            print(f"  {name}: {img.shape} -> {normalized.shape} (with keypoints)")
        else:
            normalized = normalizer(img)
            print(f"  {name}: {img.shape} -> {normalized.shape} (fallback)")
    
    print("\n2. Testing without keypoints (fallback)...")
    for name, img in test_images.items():
        normalized = normalizer(img)
        print(f"  {name}: {img.shape} -> {normalized.shape}")
    
    print("\nGeometric normalization tests completed!")
