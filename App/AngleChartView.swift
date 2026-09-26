import Charts
import SwiftUI

/// Hinge angle over time as an orange line, with an optional green replay cursor.
struct AngleChartView: View {
  var samples: [Sample]
  /// Replay position in seconds, or nil when not replaying.
  var cursorTime: Double?

  /// The x-axis spans the recording, and at least 1 s so a short recording isn't squashed.
  private var endTime: Double {
    max(samples.last?.t ?? 0, 1)
  }

  var body: some View {
    if samples.isEmpty {
      Text("Chart appears when you record")
        .font(.system(.subheadline, design: .rounded))
        .foregroundStyle(.gray)
        .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
    } else {
      Chart {
        ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
          LineMark(
            x: .value("Time", sample.t),
            y: .value("Hinge", sample.hingeDegrees)
          )
          .foregroundStyle(.orange)
          .lineStyle(StrokeStyle(lineWidth: 3))
        }
        if let cursorTime {
          RuleMark(x: .value("Replay", cursorTime))
            .foregroundStyle(.green)
            .lineStyle(StrokeStyle(lineWidth: 3))
        }
      }
      .chartYScale(domain: 0...180)
      .chartXScale(domain: 0...endTime)
      .chartYAxis {
        AxisMarks(values: [0, 90, 180]) { value in
          AxisGridLine().foregroundStyle(.gray.opacity(0.5))
          AxisValueLabel {
            if let degrees = value.as(Int.self) {
              Text("\(degrees)°")
            }
          }
          .foregroundStyle(.gray)
        }
      }
      .chartXAxis {
        AxisMarks { value in
          AxisGridLine().foregroundStyle(.gray.opacity(0.25))
          AxisValueLabel {
            if let seconds = value.as(Double.self) {
              Text("\(seconds.formatted()) s")
            }
          }
          .foregroundStyle(.gray)
        }
      }
      .frame(minHeight: 120)
      .accessibilityLabel("Hinge angle over time")
    }
  }
}
