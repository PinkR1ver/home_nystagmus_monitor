import SwiftUI

/// Compact clinical readout that keeps the live preview as the visual priority.
struct SignalPanelView: View {
  let signals: SignalFrame?
  let isReady: Bool

  var body: some View {
    HStack(spacing: 0) {
      metric(
        title: "头部方向",
        value: angleValue,
        detail: signals?.headPoseQuality.map {
          String(format: "FCQ %.0f%%", $0 * 100)
        } ?? "等待头部",
        color: RehabPalette.sky,
        symbol: "move.3d"
      )

      divider

      metric(
        title: "眼动方向",
        value: gazeValue,
        detail: signals?.gazeQuality.map {
          String(format: "Swin %.0f%%", $0 * 100)
        } ?? "等待眼部",
        color: RehabPalette.amber,
        symbol: "eye"
      )

      divider

      metric(
        title: "立体人体",
        value: depthValue,
        detail: signals?.hasStereoBodySignal == true ? "广角 + 超广角" : "等待深度",
        color: RehabPalette.mint,
        symbol: "figure.stand.line.dotted.figure.stand"
      )
    }
    .padding(.horizontal, 12)
    .redacted(reason: !isReady ? .placeholder : [])
    .accessibilityElement(children: .contain)
  }

  private var divider: some View {
    Rectangle()
      .fill(.white.opacity(0.10))
      .frame(width: 1, height: 48)
  }

  private func metric(
    title: String,
    value: String,
    detail: String,
    color: Color,
    symbol: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Label(title, systemImage: symbol)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
        .lineLimit(1)

      Text(value)
        .font(.title3.weight(.semibold).monospacedDigit())
        .foregroundStyle(.white)
        .contentTransition(.numericText())
        .lineLimit(1)
        .minimumScaleFactor(0.75)

      Text(detail)
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.48))
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 10)
  }

  private var angleValue: String {
    guard let value = signals?.headYaw else { return "—" }
    return String(format: "%+.1f°", value)
  }

  private var gazeValue: String {
    guard let value = signals?.gazeDirectionX else { return "—" }
    return String(format: "%+.1f°", value)
  }

  private var depthValue: String {
    guard let value = signals?.medianBodyDepthMeters else { return "—" }
    return String(format: "%.2f m", value)
  }
}
