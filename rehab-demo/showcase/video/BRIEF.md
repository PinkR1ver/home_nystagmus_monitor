---
workflow: general-video
flow: automation
storyboard: no
message: "双后摄让居家康复从二维观察升级为可量化的三信号立体评估"
destination: demo-presentation
aspect: 1920x1080
language: zh-CN
audience: "项目评审、临床合作方与技术团队"
length: 19s
angle: product-demo
---

## Intent

做一支无需旁白也能看懂的模型演示视频。画面持续保持左右分屏：左侧是
真实演示素材，右侧是同步生成的人体、头动、眼动、深度和性能数据。

## Assets

- `assets/body-walk-once-hold-v5.mp4` — 一次完整实验室步行，YOLO 骨架逐帧叠加；结束后短暂停留，不循环。
- `assets/gaze-once-hold-v5.mp4` — 1.8 秒原始眼动只播放一次；结束后定格展示后处理结果。
- `assets/demo-signals-v5.js` — 与两段单次播放素材同步的姿态和眼震相位数据。

## Customizations

- 右侧仪表区使用可读的动态曲线、3D 骨架、角度和延迟数字。
- 所有合成数值标注“演示数据”，避免将其误解为临床测量。

## Notes

- 无旁白、无背景音乐；演示现场可由讲解者口述。
- 保持临床科技感，但避免通用霓虹 HUD 和过度玻璃拟态。
- 模型组合：YOLO11n Pose、FCQ Head Pose、SwinUNet Gaze。
- 身体检测和眼部检测各播放一遍，禁止循环或重复动作。
