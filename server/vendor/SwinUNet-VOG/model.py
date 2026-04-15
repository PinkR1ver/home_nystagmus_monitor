"""
SwinUNet-based models for:
1. Gaze Estimation: Eye images (36x60) -> 3D gaze vector
2. Head Pose Estimation: Face images (224x224) -> 3x3 rotation matrix

Model Architecture:
- GazeSwinUNet: Custom lightweight SwinUNet for eye ROI (MPIIGaze)
- HeadPoseSwinUNet: timm-based Swin Transformer for full face (BIWI)
"""

import math
import torch
import torch.nn as nn
import torch.nn.functional as F

try:
    import timm
    TIMM_AVAILABLE = True
except ImportError:
    TIMM_AVAILABLE = False


class SwinUNet(nn.Module):
    """SwinUNet-inspired architecture for Gaze Estimation."""

    def __init__(self, img_size=(36, 60), in_chans=3, embed_dim=96, depths=[2, 2, 2],
                 num_heads=[3, 6, 12], window_size=7, drop_rate=0.1):
        super().__init__()

        self.embed_dim = embed_dim
        
        # Patch embedding
        self.patch_embed = nn.Conv2d(in_chans, embed_dim, kernel_size=2, stride=2)
        
        # Encoder blocks
        self.encoder_blocks = nn.ModuleList()
        in_dim = embed_dim
        for i, depth in enumerate(depths):
            for _ in range(depth):
                self.encoder_blocks.append(SwinBlock(in_dim, num_heads[i], window_size, drop_rate))
            if i < len(depths) - 1:
                out_dim = in_dim * 2
                self.encoder_blocks.append(ConvPatchMerging(in_dim, out_dim))
                in_dim = out_dim
        
        # Bottleneck
        self.bottleneck = SwinBlock(in_dim, num_heads[-1], window_size, drop_rate)
        
        # Decoder blocks
        self.decoder_blocks = nn.ModuleList()
        for i in range(len(depths) - 1):
            out_dim = in_dim // 2
            # Upsample with channel adjustment
            self.decoder_blocks.append(nn.Sequential(
                SwinBlock(in_dim, num_heads[len(depths)-2-i], window_size, drop_rate),
                nn.ConvTranspose2d(in_dim, out_dim, kernel_size=2, stride=2)
            ))
            in_dim = out_dim
        
        # Final upsampling to original size
        self.final_up = nn.Sequential(
            nn.ConvTranspose2d(in_dim, in_dim, kernel_size=2, stride=2),
            nn.Conv2d(in_dim, in_dim, kernel_size=3, padding=1),
            nn.Conv2d(in_dim, in_dim, kernel_size=3, padding=1)
        )
        
        # Regression head
        self.head = nn.Sequential(
            nn.AdaptiveAvgPool2d((1, 1)),
            nn.Flatten(),
            nn.Linear(in_dim, 256),
            nn.ReLU(inplace=True),
            nn.Dropout(drop_rate),
            nn.Linear(256, 128),
            nn.ReLU(inplace=True),
            nn.Dropout(drop_rate),
            nn.Linear(128, 3)  # 3D gaze vector
        )
        
    def forward(self, x):
        # Patch embedding
        x = self.patch_embed(x)  # B, C, 18, 30
        
        # Encoder
        for block in self.encoder_blocks:
            x = block(x)
        
        # Bottleneck
        x = self.bottleneck(x)
        
        # Decoder
        for block in self.decoder_blocks:
            x = block(x)
        
        # Final upsampling
        x = self.final_up(x)
        
        # Regression head
        x = self.head(x)
        return x


class SwinBlock(nn.Module):
    """Simplified Swin Transformer Block with depthwise separable convolution."""
    
    def __init__(self, dim, num_heads, window_size, drop_rate):
        super().__init__()
        self.dim = dim
        self.window_size = window_size
        
        # Simplified attention using depthwise conv
        self.norm1 = nn.BatchNorm2d(dim)
        self.attn = nn.Sequential(
            nn.Conv2d(dim, dim, kernel_size=window_size, padding=window_size//2, groups=dim),
            nn.Conv2d(dim, dim, kernel_size=1),
        )
        
        # MLP
        self.norm2 = nn.BatchNorm2d(dim)
        self.mlp = nn.Sequential(
            nn.Conv2d(dim, dim * 4, kernel_size=1),
            nn.GELU(),
            nn.Dropout2d(drop_rate),
            nn.Conv2d(dim * 4, dim, kernel_size=1),
            nn.Dropout2d(drop_rate)
        )
        
        self.drop_path = DropPath(drop_rate) if drop_rate > 0 else nn.Identity()
    
    def forward(self, x):
        # Attention
        shortcut = x
        x = self.norm1(x)
        x_attn = self.attn(x)
        x = x + self.drop_path(x_attn)
        
        # MLP
        x_mlp = self.mlp(self.norm2(x))
        x = x + self.drop_path(x_mlp)
        
        return x


class ConvPatchMerging(nn.Module):
    """Convolution-based patch merging (downsampling)."""
    
    def __init__(self, in_dim, out_dim):
        super().__init__()
        self.merging = nn.Sequential(
            nn.Conv2d(in_dim, out_dim, kernel_size=2, stride=2),
            nn.BatchNorm2d(out_dim)
        )
    
    def forward(self, x):
        return self.merging(x)


class DropPath(nn.Module):
    """Stochastic Depth."""
    def __init__(self, drop_prob=0.1):
        super(DropPath, self).__init__()
        self.drop_prob = drop_prob

    def forward(self, x):
        if self.drop_prob == 0. or not self.training:
            return x
        keep_prob = 1 - self.drop_prob
        random_tensor = keep_prob + torch.rand((x.size()[0], *([1] * (len(x.size()) - 1))), 
                                               dtype=x.dtype, device=x.device)
        random_tensor.floor_()
        output = x.div(keep_prob) * random_tensor
        return output


# Alias for clarity
GazeSwinUNet = SwinUNet


# ============================================================================
# Head Pose Estimation Model (BIWI dataset, 224x224 input)
# ============================================================================

class HeadPoseUpBlock(nn.Module):
    """UNet-style upsampling + skip-connection block for HeadPoseSwinUNet."""

    def __init__(self, in_channels: int, skip_channels: int) -> None:
        super().__init__()
        self.up = nn.ConvTranspose2d(in_channels, skip_channels, kernel_size=2, stride=2)
        self.conv = nn.Sequential(
            nn.Conv2d(skip_channels * 2, skip_channels, kernel_size=3, padding=1),
            nn.BatchNorm2d(skip_channels),
            nn.ReLU(inplace=True),
            nn.Conv2d(skip_channels, skip_channels, kernel_size=3, padding=1),
            nn.BatchNorm2d(skip_channels),
            nn.ReLU(inplace=True),
        )

    def forward(self, x: torch.Tensor, skip: torch.Tensor) -> torch.Tensor:
        x = self.up(x)
        if x.shape[-2:] != skip.shape[-2:]:
            x = F.interpolate(x, size=skip.shape[-2:], mode="bilinear", align_corners=False)
        x = torch.cat([x, skip], dim=1)
        x = self.conv(x)
        return x


class HeadPoseSwinUNet(nn.Module):
    """
    Head Pose Estimation model using Swin Transformer encoder (timm).
    
    Input: Face image (B, 3, 224, 224)
    Output: Rotation matrix flattened (B, 9) -> reshape to (B, 3, 3)
    
    The rotation matrix R represents head orientation in camera coordinates.
    To get yaw/pitch angles:
        fx, fy, fz = R[:, 0, 2], R[:, 1, 2], R[:, 2, 2]  # Forward vector
        yaw = atan2(-fx, fz)
        pitch = atan2(fy, sqrt(fx^2 + fz^2))
    """

    def __init__(
        self,
        backbone: str = "swin_tiny_patch4_window7_224",
        pretrained: bool = False,  # Set False for inference (weights from checkpoint)
        dropout: float = 0.3,
        num_outputs: int = 9,  # 3x3 rotation matrix
    ) -> None:
        super().__init__()
        
        if not TIMM_AVAILABLE:
            raise ImportError(
                "timm is required for HeadPoseSwinUNet. Install via `pip install timm`."
            )

        # Swin Transformer encoder with multi-scale features
        self.encoder = timm.create_model(
            backbone,
            pretrained=pretrained,
            features_only=True,
            out_indices=(0, 1, 2, 3),
        )
        encoder_channels = self.encoder.feature_info.channels()
        c0, c1, c2, c3 = encoder_channels  # e.g., [96, 192, 384, 768]

        # Bottleneck
        self.bottleneck = nn.Sequential(
            nn.Conv2d(c3, c3, kernel_size=3, padding=1),
            nn.BatchNorm2d(c3),
            nn.ReLU(inplace=True),
        )

        # UNet decoder
        self.up3 = HeadPoseUpBlock(c3, c2)
        self.up2 = HeadPoseUpBlock(c2, c1)
        self.up1 = HeadPoseUpBlock(c1, c0)

        # Final upsampling
        self.up0 = nn.Sequential(
            nn.ConvTranspose2d(c0, c0 // 2, kernel_size=2, stride=2),
            nn.BatchNorm2d(c0 // 2),
            nn.ReLU(inplace=True),
            nn.Conv2d(c0 // 2, c0 // 2, kernel_size=3, padding=1),
            nn.BatchNorm2d(c0 // 2),
            nn.ReLU(inplace=True),
        )

        # Regression head: global pool + MLP -> rotation matrix (9 values)
        final_dim = c0 // 2
        self.head = nn.Sequential(
            nn.AdaptiveAvgPool2d(1),
            nn.Flatten(),
            nn.Dropout(dropout),
            nn.Linear(final_dim, 128),
            nn.ReLU(inplace=True),
            nn.Linear(128, num_outputs),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # Swin encoder -> 4 scales
        features = self.encoder(x)
        x0, x1, x2, x3 = features

        # Handle NHWC -> NCHW if needed (some timm versions)
        def to_nchw(feat: torch.Tensor) -> torch.Tensor:
            if feat.ndim == 4 and feat.shape[1] not in self.encoder.feature_info.channels():
                return feat.permute(0, 3, 1, 2).contiguous()
            return feat

        x0, x1, x2, x3 = to_nchw(x0), to_nchw(x1), to_nchw(x2), to_nchw(x3)

        # Bottleneck + decoder
        x = self.bottleneck(x3)
        x = self.up3(x, x2)
        x = self.up2(x, x1)
        x = self.up1(x, x0)
        x = self.up0(x)

        # Regression output (B, 9)
        out = self.head(x)
        return out
    
    @staticmethod
    def rotmat_to_yaw_pitch(R: torch.Tensor) -> tuple:
        """
        Convert rotation matrix to yaw/pitch angles (degrees).
        
        Args:
            R: (B, 3, 3) or (B, 9) rotation matrix
            
        Returns:
            yaw_deg, pitch_deg: (B,) tensors in degrees
        """
        if R.dim() == 2 and R.shape[-1] == 9:
            R = R.view(-1, 3, 3)
        
        # Forward vector is 3rd column of R
        fx = R[:, 0, 2]
        fy = R[:, 1, 2]
        fz = R[:, 2, 2]
        
        # Yaw: left-right rotation
        yaw = torch.atan2(-fx, fz)
        
        # Pitch: up-down rotation
        pitch = torch.atan2(fy, torch.sqrt(fx * fx + fz * fz))
        
        # Convert to degrees
        yaw_deg = torch.rad2deg(yaw)
        pitch_deg = torch.rad2deg(pitch)
        
        return yaw_deg, pitch_deg


def build_gaze_model(checkpoint_path: str = None, device: torch.device = None) -> GazeSwinUNet:
    """Build and optionally load gaze estimation model."""
    model = GazeSwinUNet(
        img_size=(36, 60),
        in_chans=3,
        embed_dim=96,
        depths=[2, 2, 2],
        num_heads=[3, 6, 12],
        window_size=7,
        drop_rate=0.1
    )
    
    if checkpoint_path:
        if device is None:
            device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
        checkpoint = torch.load(checkpoint_path, map_location=device)
        model.load_state_dict(checkpoint['model_state_dict'])
        model.to(device)
        model.eval()
    
    return model


def build_head_pose_model(checkpoint_path: str = None, device: torch.device = None) -> HeadPoseSwinUNet:
    """Build and optionally load head pose estimation model."""
    model = HeadPoseSwinUNet(
        backbone="swin_tiny_patch4_window7_224",
        pretrained=False,
        dropout=0.3,
        num_outputs=9
    )
    
    if checkpoint_path:
        if device is None:
            device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
        checkpoint = torch.load(checkpoint_path, map_location=device)
        model.load_state_dict(checkpoint['model_state_dict'])
        model.to(device)
        model.eval()
    
    return model


if __name__ == "__main__":
    print("=" * 60)
    print("Testing Gaze Estimation Model (GazeSwinUNet)")
    print("=" * 60)
    
    gaze_model = GazeSwinUNet(
        img_size=(36, 60),
        in_chans=3,
        embed_dim=96,
        depths=[2, 2, 2],
        num_heads=[3, 6, 12],
        window_size=7
    )
    
    print(f"Gaze Model Parameters: {sum(p.numel() for p in gaze_model.parameters()):,}")
    
    x_eye = torch.randn(2, 3, 36, 60)
    with torch.no_grad():
        gaze_output = gaze_model(x_eye)
    print(f"Gaze Input: {x_eye.shape} -> Output: {gaze_output.shape}")
    
    if TIMM_AVAILABLE:
        print("\n" + "=" * 60)
        print("Testing Head Pose Model (HeadPoseSwinUNet)")
        print("=" * 60)
        
        head_model = HeadPoseSwinUNet(
            backbone="swin_tiny_patch4_window7_224",
            pretrained=False,
            dropout=0.3,
            num_outputs=9
        )
        
        print(f"Head Pose Model Parameters: {sum(p.numel() for p in head_model.parameters()):,}")
        
        x_face = torch.randn(2, 3, 224, 224)
        with torch.no_grad():
            head_output = head_model(x_face)
        print(f"Head Pose Input: {x_face.shape} -> Output: {head_output.shape}")
        
        # Test angle conversion
        R = head_output.view(-1, 3, 3)
        yaw, pitch = HeadPoseSwinUNet.rotmat_to_yaw_pitch(R)
        print(f"Yaw: {yaw}, Pitch: {pitch}")
    else:
        print("\n[WARNING] timm not installed, HeadPoseSwinUNet test skipped.")
    
    print("\nAll model tests completed!")
