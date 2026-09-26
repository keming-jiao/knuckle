import Foundation
import Observation

/// Sends the gripper value (0-100) to the local Python bridge that drives the real robot gripper.
/// At most ~20 requests a second, only the newest value, and never blocks or crashes on failure.
@Observable
final class ArmLink {
  enum Status {
    case off
    case ok
    case failing
  }

  private(set) var status = Status.off

  var isEnabled = false {
    didSet {
      guard isEnabled != oldValue else { return }
      if isEnabled {
        // Send the current value right away when the link is turned on.
        lastSent = nil
        if let latest { update(gripper: latest) }
      } else {
        pending = nil
        status = .off
      }
    }
  }

  private let url = URL(string: "http://127.0.0.1:8765/gripper")!
  private let minInterval = 1.0 / 20.0
  private let session: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 0.5
    config.timeoutIntervalForResource = 0.5
    return URLSession(configuration: config)
  }()

  /// Newest value from the screen, even while the link is off.
  private var latest: Double?
  /// Last value the bridge accepted.
  private var lastSent: Double?
  /// Value waiting to be sent. Only the newest is kept; older ones are dropped.
  private var pending: Double?
  private var isSending = false

  /// Call this whenever the gripper value on screen changes (live or replay).
  func update(gripper: Double) {
    latest = gripper
    guard isEnabled else { return }
    // Skip tiny changes (less than 1).
    if let lastSent, abs(gripper - lastSent) < 1 { return }
    pending = gripper
    if !isSending {
      isSending = true
      Task { await sendLoop() }
    }
  }

  private func sendLoop() async {
    while isEnabled, let value = pending {
      pending = nil
      let started = Date.now
      let succeeded = await send(value)
      // The user may have switched the link off while the request was running.
      guard isEnabled else { break }
      status = succeeded ? .ok : .failing
      if succeeded { lastSent = value }

      // Wait out the rest of the 1/20 s slot so we never exceed ~20 requests a second.
      let remaining = minInterval - Date.now.timeIntervalSince(started)
      if remaining > 0 {
        try? await Task.sleep(for: .seconds(remaining))
      }
    }
    isSending = false
  }

  private func send(_ gripper: Double) async -> Bool {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let rounded = (gripper * 10).rounded() / 10
    request.httpBody = try? JSONSerialization.data(withJSONObject: ["gripper": rounded])

    do {
      let (_, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse else { return false }
      return (200..<300).contains(http.statusCode)
    } catch {
      // Timeout, bridge not running, etc. The red dot is the only signal.
      return false
    }
  }
}
