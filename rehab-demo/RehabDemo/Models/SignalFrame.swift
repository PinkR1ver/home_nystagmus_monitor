import Foundation

/// 单帧三信号输出：立体人体、独立头动与眼动。
struct SignalFrame: Identifiable {
  let id = UUID()
  let timestamp: Date

  /// 全身关键点（YOLO11 COCO Pose 17 点 + neck/root 两个派生点）
  let bodyLandmarks: [BodyLandmarkPoint]

  /// 头部 —— 方向
  let headYaw: Double?
  let headPitch: Double?
  let headRoll: Double?

  /// 眼动模型输出
  let eyeOpenness: Double?
  let gazeDirectionX: Double?
  let gazeDirectionY: Double?

  /// 身体 —— 姿势摆动
  let comDisplacement: Double?

  /// 第三方模型给出的当前人物置信度
  let personConfidence: Double

  /// 双后摄视差深度对姿态关键点的覆盖率
  let stereoDepthCoverage: Double
  let medianBodyDepthMeters: Double?
  let hasStereoBodySignal: Bool

  /// 独立头动和眼动模型的输入质量
  let headPoseQuality: Double?
  let gazeQuality: Double?

  let modelName: String

  /// 当前帧是否检测到人
  var personDetected: Bool { !bodyLandmarks.isEmpty }
}

struct BodyLandmarkPoint: Identifiable {
  let id = UUID()
  /// COCO Pose 名称，使用 snake_case。
  let identifier: String
  /// Vision 归一化坐标 (0…1)，左上角为原点
  let x: Double
  let y: Double
  let confidence: Double

  /// 由双后摄深度与相机内参投影得到的相机坐标（米）。
  let cameraX: Double?
  let cameraY: Double?
  let cameraZ: Double?

  init(
    identifier: String,
    x: Double,
    y: Double,
    confidence: Double,
    cameraX: Double? = nil,
    cameraY: Double? = nil,
    cameraZ: Double? = nil
  ) {
    self.identifier = identifier
    self.x = x
    self.y = y
    self.confidence = confidence
    self.cameraX = cameraX
    self.cameraY = cameraY
    self.cameraZ = cameraZ
  }
}
