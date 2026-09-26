import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// The file the share sheet sends: knuckle_<episode_id>.json.
/// The JSON is only built when the user actually shares, off the main thread,
/// so everything here is `nonisolated`.
nonisolated struct EpisodeFile: Transferable, Sendable {
  var episode: Episode

  var episodeID: String {
    episode.id.uuidString.lowercased()
  }

  var fileName: String {
    "knuckle_\(episodeID).json"
  }

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(exportedContentType: .json) { file in
      let url = URL.temporaryDirectory.appending(path: file.fileName)
      try file.jsonData().write(to: url, options: .atomic)
      return SentTransferredFile(url)
    }
  }

  func jsonData() throws -> Data {
    let json = EpisodeJSON(
      episodeID: episodeID,
      createdAt: episode.createdAt,
      sampleRateHz: Int(Recorder.sampleRate),
      samples: episode.samples.map { sample in
        SampleJSON(
          t: rounded(sample.t, decimals: 2),
          hingeDeg: rounded(sample.hingeDegrees, decimals: 1),
          // Same function the screen uses, so the file and the screen always agree.
          gripper: rounded(gripperValue(hingeDegrees: sample.hingeDegrees), decimals: 1)
        )
      }
    )
    let encoder = JSONEncoder()
    // ISO-8601 in UTC, e.g. 2026-09-26T05:00:15Z.
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    return try encoder.encode(json)
  }

  private func rounded(_ value: Double, decimals: Int) -> Double {
    let scale = pow(10, Double(decimals))
    return (value * scale).rounded() / scale
  }
}

/// The top level of the JSON file. Key names match the schema in CLAUDE.md.
nonisolated struct EpisodeJSON: Encodable, Sendable {
  var episodeID: String
  var createdAt: Date
  var sampleRateHz: Int
  var samples: [SampleJSON]

  enum CodingKeys: String, CodingKey {
    case episodeID = "episode_id"
    case createdAt = "created_at"
    case sampleRateHz = "sample_rate_hz"
    case samples
  }
}

/// One sample in the JSON file.
nonisolated struct SampleJSON: Encodable, Sendable {
  var t: Double
  var hingeDeg: Double
  var gripper: Double

  enum CodingKeys: String, CodingKey {
    case t
    case hingeDeg = "hinge_deg"
    case gripper
  }
}
