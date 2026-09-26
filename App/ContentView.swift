import SwiftUI

struct ContentView: View {
  /// Latest real hinge angle in degrees. Nil until the first hinge update (or on a device without a hinge).
  @State private var hingeDegrees: Double?
  @State private var hingeStatus: DeviceHinge.Status?
  @State private var recorder = Recorder()
  @State private var armLink = ArmLink()

  /// During replay the recorded angle drives the screen; otherwise the live hinge does.
  private var shownDegrees: Double? {
    recorder.isReplaying ? recorder.replayDegrees : hingeDegrees
  }

  private var gripper: Double {
    gripperValue(hingeDegrees: shownDegrees ?? 0)
  }

  var body: some View {
    ZStack {
      // Background sits behind the whole arrangement so the fold gap is black too.
      Color.black.ignoresSafeArea()

      if hingeStatus == .closed {
        // Centered on the whole screen, not just the safe area.
        Text("Open to start")
          .font(.system(.largeTitle, design: .rounded, weight: .semibold))
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .ignoresSafeArea()
      } else {
        ArrangementView {
          GripperDrawing(gripper: gripper)
            .reservedRegionPadding()
            // Live: short ease-out. Replay: already smooth at 60 fps, so no extra animation.
            .animation(recorder.isReplaying ? nil : .easeOut(duration: 0.1), value: gripper)
        } secondary: {
          controls
        }
        .arrangementViewStyle(.split)
      }
    }
    // Feed the robot arm whatever the screen shows: live hinge or replay.
    .onChange(of: shownDegrees) {
      guard shownDegrees != nil else { return }
      armLink.update(gripper: gripper)
    }
    // Live hinge input is paused while replaying.
    .onHingeChange(isEnabled: !recorder.isReplaying) { _, newContext in
      // hinge is nil on devices without a hinge, so always unwrap it.
      guard let hinge = newContext.hinge else { return }
      hingeDegrees = hinge.angle.degrees
      hingeStatus = hinge.status
      recorder.latestHingeDegrees = hinge.angle.degrees
      if hinge.status == .closed && recorder.isRecording {
        recorder.stop()
      }
    }
  }

  // MARK: Controls pane

  private var controls: some View {
    GeometryReader { proxy in
      // Pick the layout from the pane's real size, not from the crease direction.
      let isWide = proxy.size.width > proxy.size.height
      // Shrink the big numbers a little when the pane is short, so the chart keeps its space.
      let numberSize = readoutNumberSize(for: proxy.size, isWide: isWide)

      Group {
        if isWide {
          HStack(spacing: 32) {
            infoColumn(numberSize: numberSize)
            VStack(spacing: 16) {
              buttons
              chart(fillsHeight: true)
            }
          }
        } else {
          VStack(spacing: 20) {
            infoColumn(numberSize: numberSize)
            buttons
            // One column: the chart keeps just its 120 pt so the numbers get the space.
            chart(fillsHeight: false)
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    // Keeps everything 24 pt from the fold and clear of the status-bar strip.
    .reservedRegionPadding()
  }

  private func infoColumn(numberSize: CGFloat) -> some View {
    VStack(spacing: 12) {
      statusLine
      timerLine
      HStack(spacing: 32) {
        Readout(label: "HINGE", value: hingeText, numberSize: numberSize)
        Readout(label: "GRIPPER", value: gripperText, numberSize: numberSize)
      }
      armLinkToggle
    }
    .frame(maxWidth: .infinity)
  }

  private var armLinkToggle: some View {
    HStack(spacing: 10) {
      Circle()
        .fill(armLinkColor)
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
      Toggle("Arm link", isOn: $armLink.isEnabled)
        .font(.system(.headline, design: .rounded))
        .foregroundStyle(.white)
        .fixedSize()
        .accessibilityValue(armLinkAccessibilityValue)
    }
  }

  private var armLinkColor: Color {
    switch armLink.status {
    case .off: .gray
    case .ok: .green
    case .failing: .red
    }
  }

  private var armLinkAccessibilityValue: String {
    switch armLink.status {
    case .off: "Off"
    case .ok: "Connected"
    case .failing: "Not responding"
    }
  }

  /// The biggest number size the pane allows, estimated from the space the other
  /// controls need (status, timer, buttons, and the 120 pt chart in one column).
  /// minimumScaleFactor on the numbers is the safety net if the estimate is a bit high.
  private func readoutNumberSize(for size: CGSize, isWide: Bool) -> CGFloat {
    // Height left for the number after status, timer, label, toggle and spacing
    // (and, in one column, the buttons and chart too). The number's line is ~1.25x its size.
    let otherHeight: CGFloat = isWide ? 190 : 480
    let byHeight = (size.height - otherHeight) / 1.25
    // Two readouts side by side, each up to ~4 characters ("180°") at ~0.6x size wide.
    let columnWidth = isWide ? (size.width - 32) / 2 : size.width
    let byWidth = (columnWidth - 32) / 4.8
    return min(160, max(Readout.minimumNumberSize, min(byHeight, byWidth)))
  }

  @ViewBuilder
  private func chart(fillsHeight: Bool) -> some View {
    let chart = AngleChartView(
      samples: recorder.chartSamples,
      cursorTime: recorder.isReplaying ? recorder.replayTime : nil
    )
    if fillsHeight {
      // Two columns: the chart takes the leftover height, but never less than 120 pt.
      chart
        .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
        .layoutPriority(1)
    } else {
      chart
        .frame(maxWidth: .infinity)
        .frame(height: 120)
    }
  }

  @ViewBuilder
  private var statusLine: some View {
    switch recorder.mode {
    case .recording:
      Text("Close the phone to stop.")
        .font(.system(.title3, design: .rounded))
        .foregroundStyle(.gray)
    case .replaying:
      Text("REPLAYING")
        .font(.system(.title, design: .rounded, weight: .heavy))
        .foregroundStyle(.green)
    case .idle:
      Text(savedText)
        .font(.system(.title2, design: .rounded, weight: .semibold))
        .foregroundStyle(.white)
    }
  }

  @ViewBuilder
  private var timerLine: some View {
    switch recorder.mode {
    case .recording:
      Text("● REC \(formatTime(recorder.recordingElapsed))")
        .foregroundStyle(.red)
        .font(.system(.title, design: .rounded, weight: .bold))
        .monospacedDigit()
    case .replaying:
      Text("▶ \(formatTime(recorder.replayTime)) / \(formatTime(recorder.episode?.duration ?? 0))")
        .foregroundStyle(.green)
        .font(.system(.title, design: .rounded, weight: .bold))
        .monospacedDigit()
    case .idle:
      EmptyView()
    }
  }

  private var buttons: some View {
    // One row if every label fits at full size, otherwise a 2 x 2 grid.
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 12) {
        recordButton
        stopButton
        replayButton
        exportButton
      }
      Grid(horizontalSpacing: 12, verticalSpacing: 12) {
        GridRow {
          recordButton
          stopButton
        }
        GridRow {
          replayButton
          exportButton
        }
      }
    }
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private var exportButton: some View {
    // Opens the share sheet (Save to Files / AirDrop) with knuckle_<episode_id>.json.
    if let episode = recorder.episode {
      let file = EpisodeFile(episode: episode)
      ShareLink(item: file, preview: SharePreview(file.fileName)) {
        Label("Export", systemImage: "square.and.arrow.up")
      }
      .buttonStyle(ColoredButtonStyle(color: .cyan))
      .disabled(recorder.mode != .idle)
    } else {
      // Nothing recorded yet: same look, always disabled.
      Button("Export", systemImage: "square.and.arrow.up") {}
        .buttonStyle(ColoredButtonStyle(color: .cyan))
        .disabled(true)
    }
  }

  private var recordButton: some View {
    Button("Record", systemImage: "record.circle") {
      recorder.startRecording()
    }
    .buttonStyle(ColoredButtonStyle(color: .red, textColor: .white))
    .disabled(recorder.mode != .idle)
  }

  private var stopButton: some View {
    Button("Stop", systemImage: "stop.fill") {
      recorder.stop()
    }
    .buttonStyle(ColoredButtonStyle(color: .white))
    .disabled(recorder.mode == .idle)
  }

  private var replayButton: some View {
    Button("Replay", systemImage: "play.fill") {
      recorder.startReplay()
    }
    .buttonStyle(ColoredButtonStyle(color: .green))
    .disabled(recorder.mode != .idle || recorder.episode == nil)
  }

  // MARK: Text

  private var savedText: String {
    guard let episode = recorder.episode else { return "No recording yet" }
    return "Saved: \(episode.duration.formatted(.number.precision(.fractionLength(1)))) s"
  }

  private var hingeText: String {
    guard let shownDegrees else { return "--" }
    return "\(Int(shownDegrees.rounded()))°"
  }

  private var gripperText: String {
    guard shownDegrees != nil else { return "--" }
    return "\(Int(gripper.rounded()))"
  }

  /// Formats seconds as "0:03.2".
  private func formatTime(_ seconds: Double) -> String {
    let tenths = Int((seconds * 10).rounded(.down))
    let minutes = tenths / 600
    let wholeSeconds = (tenths % 600) / 10
    let tenth = tenths % 10
    let paddedSeconds = wholeSeconds < 10 ? "0\(wholeSeconds)" : "\(wholeSeconds)"
    return "\(minutes):\(paddedSeconds).\(tenth)"
  }
}

/// A small gray label above a large bold number.
private struct Readout: View {
  var label: String
  var value: String
  var numberSize: CGFloat = 64

  /// Numbers never get smaller than this, in any pose.
  static let minimumNumberSize: CGFloat = 56

  var body: some View {
    VStack(spacing: 4) {
      Text(label)
        .font(.system(.headline, design: .rounded))
        .foregroundStyle(.gray)
      Text(value)
        .font(.system(size: numberSize, weight: .bold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(.white)
        .lineLimit(1)
        // May shrink to fit, but never below the 56 pt floor.
        .minimumScaleFactor(min(1, Self.minimumNumberSize / numberSize))
    }
    .accessibilityElement(children: .combine)
  }
}
