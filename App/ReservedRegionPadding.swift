import SwiftUI

/// Pads a pane by 24 pt on every side, and more on any side that faces the fold
/// or the status-bar strip, so content stays at least 24 pt from the fold.
/// If no fold region is reported, the plain 24 pt padding still covers the fold-facing edge.
struct ReservedRegionPadding: ViewModifier {
  private let basePadding: CGFloat = 24
  private let foldClearance: CGFloat = 24
  private let occlusionClearance: CGFloat = 8

  func body(content: Content) -> some View {
    GeometryReader { proxy in
      content
        .padding(insets(for: proxy))
        .frame(width: proxy.size.width, height: proxy.size.height)
    }
  }

  private func insets(for proxy: GeometryProxy) -> EdgeInsets {
    // Read the regions here in the body every time; they arrive after the first layout pass.
    // The fold is INACTIVE when the phone is flat, so .includeInactive is needed to see it.
    let folds = proxy.reservedRegions(kind: .division, options: [.includeInactive])
    // The status-bar strip is an active occlusion region.
    let occlusions = proxy.reservedRegions(kind: .occlusion)
    let bounds = CGRect(origin: .zero, size: proxy.size)

    var insets = EdgeInsets(top: basePadding, leading: basePadding, bottom: basePadding, trailing: basePadding)
    for fold in folds {
      push(&insets, awayFrom: fold.frame, clearance: foldClearance, in: bounds)
    }
    for occlusion in occlusions {
      push(&insets, awayFrom: occlusion.frame, clearance: occlusionClearance, in: bounds)
    }
    return insets
  }

  /// If a region (plus its clearance) overlaps the pane, grow the padding on the one
  /// side that moves content out of it with the least space lost.
  private func push(_ insets: inout EdgeInsets, awayFrom region: CGRect, clearance: CGFloat, in bounds: CGRect) {
    let zone = region.insetBy(dx: -clearance, dy: -clearance)
    guard zone.intersects(bounds) else { return }

    let fromLeading = zone.maxX
    let fromTrailing = bounds.width - zone.minX
    let fromTop = zone.maxY
    let fromBottom = bounds.height - zone.minY
    let smallest = min(fromLeading, fromTrailing, fromTop, fromBottom)

    if smallest == fromLeading {
      insets.leading = max(insets.leading, fromLeading)
    } else if smallest == fromTrailing {
      insets.trailing = max(insets.trailing, fromTrailing)
    } else if smallest == fromTop {
      insets.top = max(insets.top, fromTop)
    } else {
      insets.bottom = max(insets.bottom, fromBottom)
    }
  }
}

extension View {
  func reservedRegionPadding() -> some View {
    modifier(ReservedRegionPadding())
  }
}
