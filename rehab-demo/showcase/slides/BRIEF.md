---
workflow: slideshow
flow: automation
storyboard: no
message: "后置广角与超广角让人体、头动和眼动进入同一套可复盘的居家评估链路"
destination: live-presentation
aspect: 1920x1080
language: zh-CN
audience: "项目评审、临床合作方与技术团队"
length: 8-slides
angle: technical-demo
---

## Intent

制作一套可直接在浏览器演示的 HTML slides，解释为什么使用两个后置镜头、
三套第三方权重模型如何协作、输出哪些数据，以及当前性能与边界。

## Assets

- `composition/assets/body-walk-overlay-v4.mp4` — 临床实验室全身步行，YOLO11n Pose 骨架逐帧直接叠加。
- `composition/assets/gaze-demo-v3.mp4` — 直接眼震特写，用于与虹膜水平位移曲线逐帧对应。
- `composition/assets/demo-signals-v4.js` — 影片和 slides 共用的实测姿态、滤波、转折点及快/慢相数据。

## Notes

- 每页只讲一个结论，标题必须是完整句子。
- 包含演讲者备注；键盘左右键翻页。
- 明确模型许可证和“演示，不用于临床诊断”的边界。
- 眼动单位明确为画面宽度百分比；连续性门未通过时不得展示阳性结论。
