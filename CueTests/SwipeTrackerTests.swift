import CoreGraphics
import Testing

@Suite("Touchpad swipes")
struct SwipeTrackerTests {
    /// Feeds a drag one point at a time, as the gesture reports it, and collects the presses.
    private func presses(along path: [CGSize]) -> [RemoteButton] {
        var tracker = SwipeTracker()
        var presses = path.compactMap { tracker.move(to: $0) }
        if let last = path.last, let button = tracker.end(at: last) { presses.append(button) }
        return presses
    }

    private func line(to end: CGSize, steps: Int = 100) -> [CGSize] {
        (1...steps).map { CGSize(width: end.width * CGFloat($0) / CGFloat(steps), height: end.height * CGFloat($0) / CGFloat(steps)) }
    }

    @Test func oneArrowPerStepOfTravel() {
        #expect(presses(along: line(to: CGSize(width: 150, height: 0))) == [.right, .right, .right])
    }

    @Test(arguments: [
        (CGSize(width: -60, height: 0), RemoteButton.left),
        (CGSize(width: 0, height: 60), .down),
        (CGSize(width: 0, height: -60), .up),
    ])
    func directionFollowsTheSwipe(end: CGSize, button: RemoteButton) {
        #expect(presses(along: line(to: end)) == [button])
    }

    @Test func diagonalSwipeFollowsItsDominantAxis() {
        #expect(presses(along: line(to: CGSize(width: 100, height: 30))) == [.right, .right])
    }

    @Test func shortSwipeSendsNothing() {
        #expect(presses(along: line(to: CGSize(width: 30, height: 0))).isEmpty)
    }

    @Test func clickWithoutTravelIsOK() {
        #expect(presses(along: [.zero, CGSize(width: 2, height: 1)]) == [.enter])
    }

    @Test func swipeDoesNotEndWithOK() {
        #expect(presses(along: line(to: CGSize(width: 50, height: 0))).last == .right)
    }

    @Test func trackerStartsOverAfterEachDrag() {
        var tracker = SwipeTracker()
        _ = tracker.move(to: CGSize(width: 60, height: 0))
        _ = tracker.end(at: CGSize(width: 60, height: 0))
        #expect(tracker.move(to: CGSize(width: 50, height: 0)) == .right)
    }
}
