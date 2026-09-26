import Foundation
import Observation

/// Maps the real hinge angle to a gripper value from 0 (closed) to 100 (open).
/// Hinge 60° or less -> 0, hinge 180° -> 100, linear in between.
/// The screen and the export both use this, so they always agree.
nonisolated func gripperValue(hingeDegrees: Double) -> Double {
  let closedAngle = 60.0
  let openAngle = 180.0
  let fraction = (hingeDegrees - closedAngle) / (openAngle - closedAngle)
  return min(max(fraction, 0), 1) * 100
}

/// Records one demonstration (hinge angle over time) and replays it.
/// This is playback of recorded data, not machine learning.
@Observable
final class Recorder {
  enum Mode {
    case idle
    case recording
    case replaying
  }

  nonisolated static let sampleRate = 30.0

  private(set) var mode = Mode.idle
  /// The one saved demonstration. A new recording replaces it.
  private(set) var episode: Episode?

  /// Seconds since Record was pressed (updated at every sample).
  private(set) var recordingElapsed = 0.0
  /// Seconds into the replay (updated about 60 times a second).
  private(set) var replayTime = 0.0
  /// Hinge angle at `replayTime`, interpolated between samples.
  private(set) var replayDegrees: Double?

  /// The newest live hinge angle. The sampler reads this every 1/30 s.
  var latestHingeDegrees = 0.0

  private let clock = ContinuousClock()
  private var startInstant: ContinuousClock.Instant?
  private var draft: Episode?
  private var task: Task<Void, Never>?

  /// What the chart shows: the recording in progress, otherwise the saved one.
  var chartSamples: [Sample] {
    draft?.samples ?? episode?.samples ?? []
  }

  var isRecording: Bool { mode == .recording }
  var isReplaying: Bool { mode == .replaying }

  // MARK: Recording

  func startRecording() {
    guard mode == .idle else { return }
    let start = clock.now
    startInstant = start
    draft = Episode(id: UUID(), createdAt: .now, samples: [])
    recordingElapsed = 0
    mode = .recording
    addSample(at: 0)

    task = Task { [weak self] in
      // Sample k is due at k/30 s after Record.
      var nextSlot = 1
      while !Task.isCancelled {
        let dueTime = start + .seconds(Double(nextSlot) / Self.sampleRate)
        try? await self?.clock.sleep(until: dueTime)
        guard let self, !Task.isCancelled, self.mode == .recording else { return }

        // If we woke up late, jump to the newest slot that is due and skip the
        // ones we missed, so a timestamp is never used twice.
        let elapsed = self.seconds(since: start)
        let dueSlot = Int((elapsed * Self.sampleRate).rounded(.down))
        let slot = max(dueSlot, nextSlot)
        self.addSample(at: Double(slot) / Self.sampleRate)
        nextSlot = slot + 1
      }
    }
  }

  func stop() {
    switch mode {
    case .idle:
      return
    case .recording:
      finishRecording()
    case .replaying:
      task?.cancel()
      task = nil
      replayDegrees = nil
      mode = .idle
    }
  }

  private func finishRecording() {
    task?.cancel()
    task = nil
    if let start = startInstant, let lastTime = draft?.samples.last?.t {
      // One final sample, unless a regular one was taken less than half a slot ago.
      let elapsed = seconds(since: start)
      if elapsed - lastTime >= 0.5 / Self.sampleRate {
        addSample(at: elapsed)
      }
    }
    episode = draft
    draft = nil
    startInstant = nil
    mode = .idle
  }

  private func addSample(at time: Double) {
    draft?.samples.append(Sample(t: time, hingeDegrees: latestHingeDegrees))
    recordingElapsed = time
  }

  // MARK: Replay

  func startReplay() {
    guard mode == .idle, let episode else { return }
    let start = clock.now
    mode = .replaying
    updateReplay(time: 0, episode: episode)

    task = Task { [weak self] in
      // A ~60 fps clock. The position comes from the real elapsed time,
      // so playback keeps the original timing even if a frame is late.
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1.0 / 60.0))
        guard let self, !Task.isCancelled, self.mode == .replaying else { return }
        let time = min(self.seconds(since: start), episode.duration)
        self.updateReplay(time: time, episode: episode)
        if time >= episode.duration {
          self.stop()
          return
        }
      }
    }
  }

  private func updateReplay(time: Double, episode: Episode) {
    replayTime = time
    replayDegrees = episode.degrees(at: time)
  }

  private func seconds(since start: ContinuousClock.Instant) -> Double {
    let duration = clock.now - start
    return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
  }
}

/// One recorded demonstration.
nonisolated struct Episode: Sendable {
  var id: UUID
  var createdAt: Date
  var samples: [Sample]

  var duration: Double {
    samples.last?.t ?? 0
  }

  /// The hinge angle at any time, drawn as a straight line between the two nearest samples.
  func degrees(at time: Double) -> Double? {
    guard let first = samples.first else { return nil }
    guard let nextIndex = samples.firstIndex(where: { $0.t > time }) else {
      return samples.last?.hingeDegrees
    }
    if nextIndex == 0 { return first.hingeDegrees }
    let before = samples[nextIndex - 1]
    let after = samples[nextIndex]
    let fraction = (time - before.t) / (after.t - before.t)
    return before.hingeDegrees + (after.hingeDegrees - before.hingeDegrees) * fraction
  }
}

/// One hinge reading, `t` seconds after Record was pressed.
nonisolated struct Sample: Sendable {
  var t: Double
  var hingeDegrees: Double
}
