import CoreGraphics

/// Turns a touchpad drag into arrow presses, one every `step` points of travel; a click without travel is OK.
struct SwipeTracker {
    var step: CGFloat = 48
    private var consumed = CGSize.zero
    private var didMove = false

    /// The press for the drag's latest translation, if it travelled one more step along its dominant axis.
    mutating func move(to translation: CGSize) -> RemoteButton? {
        let dx = translation.width - consumed.width
        let dy = translation.height - consumed.height
        if abs(dx) >= step, abs(dx) > abs(dy) {
            consumed = CGSize(width: consumed.width + (dx > 0 ? step : -step), height: translation.height)
            didMove = true
            return dx > 0 ? .right : .left
        }
        if abs(dy) >= step {
            consumed = CGSize(width: translation.width, height: consumed.height + (dy > 0 ? step : -step))
            didMove = true
            return dy > 0 ? .down : .up
        }
        return nil
    }

    /// OK for a click without travel; resets the tracker for the next drag.
    mutating func end(at translation: CGSize) -> RemoteButton? {
        defer { self = SwipeTracker(step: step) }
        return !didMove && hypot(translation.width, translation.height) < 6 ? .enter : nil
    }
}
