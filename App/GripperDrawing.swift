import SwiftUI

/// Draws the gripper as two orange jaws on a gray base.
/// Each jaw tilts outward up to 35° as the gripper value goes from 0 to 100.
struct GripperDrawing: View {
  var gripper: Double

  private var jawTilt: Double {
    gripper / 100 * 35
  }

  var body: some View {
    GeometryReader { proxy in
      // Everything is sized from the smaller side so the drawing fits any pane.
      let unit = min(proxy.size.width, proxy.size.height)
      let jawWidth = unit * 0.12
      let jawHeight = unit * 0.5
      let baseWidth = unit * 0.6
      let baseHeight = unit * 0.14

      VStack(spacing: 0) {
        HStack(spacing: unit * 0.04) {
          jaw(width: jawWidth, height: jawHeight)
            .rotationEffect(.degrees(-jawTilt), anchor: .bottom)
          jaw(width: jawWidth, height: jawHeight)
            .rotationEffect(.degrees(jawTilt), anchor: .bottom)
        }
        RoundedRectangle(cornerRadius: unit * 0.03)
          .fill(Color(white: 0.4))
          .frame(width: baseWidth, height: baseHeight)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .accessibilityElement()
    .accessibilityLabel("Gripper")
    .accessibilityValue("\(Int(gripper.rounded())) percent open")
  }

  private func jaw(width: CGFloat, height: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: width * 0.35)
      .fill(.orange)
      .frame(width: width, height: height)
  }
}
