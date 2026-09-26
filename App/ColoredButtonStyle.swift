import SwiftUI

/// A filled, rounded button in one solid color. Disabled buttons show a dimmed version of that color.
struct ColoredButtonStyle: ButtonStyle {
  var color: Color
  var textColor: Color = .black

  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(.title3, design: .rounded, weight: .bold))
      .lineLimit(1)
      .fixedSize()
      .foregroundStyle(textColor)
      .padding(.horizontal, 20)
      .padding(.vertical, 14)
      .frame(maxWidth: .infinity)
      .background(color, in: .rect(cornerRadius: 14))
      .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.3)
  }
}
