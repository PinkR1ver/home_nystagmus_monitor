---
workflow: slideshow
flow: automation
storyboard: no
message: "把论文中的模型拆成可解释、可复现的特征提取链路，并明确原模型、代理实现和临床边界"
destination: live-presentation
aspect: 1920x1080
language: zh-CN
audience: "项目团队、临床合作方与技术评审"
length: 9-slides
angle: evidence-led-technical-demo
---

## Intent

制作一套可直接在浏览器演示的简洁 HTML slides：从 BEFAST 文献中筛选可复现的模型与方法，使用开放或非临床示例数据展示 Face、Eye、Arm、Balance、Speech 如何从原始输入提取特征，并说明哪些是论文原方法、哪些是工程代理实现。

## Assets

- `assets/nystagmus-demo.mp4` — CC BY-SA 4.0 眼震示例，用于演示 aEYE 递归运动滤波与眼动轨迹。
- `assets/body-walk-overlay.mp4` — 既有步态演示素材及姿态叠加，用于展示骨架与时序特征。
- `assets/demo-signals.js` — 从现有源视频提取的眼动与人体姿态时间序列。
- `assets/upper-limb-repetitions.csv` — Pavlikov 等公开的 CC BY 4.0 重复动作指标数据子集。

## Notes

- 每页只表达一个完整结论，以模型输入、特征变换和输出证据为主要视觉。
- 原论文未公开权重或训练数据时，必须标为“方法复现”或“代理模型”，不得暗示使用了论文原始模型。
- 所有示例仅用于研究沟通，不输出临床诊断结论。
- 交付应能通过左右键导航，并包含演讲者备注和来源页。
