import Testing
@testable import GestureCore

private func p(_ x: Double, _ y: Double, _ id: Int = 1) -> TouchPoint { TouchPoint(id: id, x: x, y: y) }
private func pair(_ x: Double, _ y: Double) -> [TouchPoint] { [p(x,y), p(x,y+0.04,2)] }
private func fresh(_ s: GestureSettings = GestureSettings()) -> GestureEngine {
    var e = GestureEngine(); _ = e.process([], time: 0, settings: s); return e
}
@Test func allSingleFingerInputIsIgnored() {
    var s = GestureSettings(); s.mediaTapEnabled = true
    for x in [0.02, 0.5, 0.98] {
        for y in [0.02, 0.4, 0.92] {
            var e = fresh(s)
            _ = e.process([p(x,y)], time: 1, settings: s)
            #expect(e.process([p(x,y-0.1)], time: 1.1, settings: s).isEmpty)
            #expect(e.process([], time: 1.2, settings: s).isEmpty)
            _ = e.process([p(x,y)], time: 1.3, settings: s)
            #expect(e.process([], time: 1.4, settings: s).isEmpty)
            #expect(!e.capturesScroll)
        }
    }
}
@Test func eachEdgeCanBeDisabled() {
    for left in [true,false] {
        var s = GestureSettings(); s.leftEnabled = !left; s.rightEnabled = left
        var e = fresh(s); let x = left ? 0.02 : 0.98
        _ = e.process(pair(x,0.4), time: 1, settings: s)
        #expect(e.process(pair(x,0.6), time: 1.1, settings: s).isEmpty)
        #expect(!e.capturesPointer && !e.capturesScroll)
    }
}
@Test func centerCannotAcquireEdge() {
    let s = GestureSettings(); var e = fresh()
    _ = e.process(pair(0.5,0.4), time: 1, settings: s)
    #expect(e.process(pair(0.98,0.6), time: 1.1, settings: s).isEmpty)
}
@Test func edgeLocksAndUsesRelativeMovement() {
    let s = GestureSettings(); var e = fresh()
    _ = e.process(pair(0.98,0.4), time: 1, settings: s)
    let actions = e.process(pair(0.98,0.5), time: 1.1, settings: s)
    guard case .volume(let amount) = actions.first else { Issue.record("Expected volume"); return }
    #expect(abs(amount-0.15) < 0.0001)
    #expect(e.capturesPointer && e.capturesScroll)
    guard case .volume = e.process(pair(0.5,0.6), time: 1.2, settings: s).first else { Issue.record("Region not locked"); return }
    _ = e.process([], time: 1.3, settings: s)
    #expect(!e.capturesPointer && !e.capturesScroll)
}
@Test func controlCenterIsCornerOnlyAndFiresOnce() {
    let s = GestureSettings(); var e = fresh()
    _ = e.process(pair(0.88,0.9), time: 1, settings: s)
    #expect(e.process(pair(0.88,0.7), time: 1.1, settings: s) == [.openControlCenter])
    #expect(e.process(pair(0.88,0.5), time: 1.2, settings: s).isEmpty)
    #expect(e.process([], time: 1.3, settings: s).isEmpty)
    _ = e.process(pair(0.5,0.8), time: 2, settings: s)
    #expect(e.process(pair(0.5,0.5), time: 2.1, settings: s).isEmpty)
}
@Test func sequentialLandingAndLiftingWork() {
    var s = GestureSettings(); s.mediaTapEnabled = true
    var e = fresh(s)
    _ = e.process([p(0.4,0.02)], time: 1, settings: s)
    _ = e.process(pair(0.4,0.02), time: 1.04, settings: s)
    _ = e.process([p(0.4,0.02)], time: 1.1, settings: s)
    #expect(e.process([], time: 1.14, settings: s) == [.playPause])
}
@Test func lateSecondFingerIsIgnored() {
    let s = GestureSettings(); var e = fresh()
    _ = e.process([p(0.98,0.4)], time: 1, settings: s)
    _ = e.process(pair(0.98,0.4), time: 1.4, settings: s)
    #expect(e.process(pair(0.98,0.6), time: 1.5, settings: s).isEmpty)
}
@Test func disabledControlCenterDoesNotOpen() {
    var s = GestureSettings(); s.controlCenterEnabled = false
    var e = fresh(s)
    _ = e.process(pair(0.9,0.9), time: 1, settings: s)
    #expect(e.process(pair(0.9,0.6), time: 1.2, settings: s).isEmpty)
}
@Test func muteRequiresTwoTwoFingerTaps() {
    let s = GestureSettings(); var e = fresh()
    _ = e.process(pair(0.9,0.9), time: 1, settings: s)
    #expect(e.process([], time: 1.1, settings: s).isEmpty)
    _ = e.process(pair(0.9,0.9), time: 1.2, settings: s)
    #expect(e.process([], time: 1.3, settings: s) == [.mute])
}
@Test func mediaTapOffByDefaultAndSwipeFiresOnce() {
    let s = GestureSettings(); var e = fresh()
    _ = e.process(pair(0.4,0.02), time: 1, settings: s)
    #expect(e.process([], time: 1.1, settings: s).isEmpty)
    _ = e.process(pair(0.4,0.02), time: 2, settings: s)
    #expect(e.process(pair(0.6,0.02), time: 2.1, settings: s) == [.nextTrack])
    #expect(e.process(pair(0.8,0.02), time: 2.2, settings: s).isEmpty)
    #expect(e.process([], time: 2.3, settings: s).isEmpty)
}
@Test func changingSettingsCancelsCapture() {
    var s = GestureSettings(); var e = fresh()
    _ = e.process(pair(0.98,0.4), time: 1, settings: s)
    _ = e.process(pair(0.98,0.5), time: 1.1, settings: s)
    s.rightEnabled = false
    #expect(e.process(pair(0.98,0.7), time: 1.2, settings: s).isEmpty)
    #expect(!e.capturesPointer && !e.capturesScroll)
}
@Test func clickAndThirdFingerCancel() {
    let s = GestureSettings(); var e = fresh()
    _ = e.process(pair(0.98,0.4), time: 1, settings: s)
    #expect(e.process(pair(0.98,0.6), time: 1.1, settings: s, mouseDown: true).isEmpty)
    _ = e.process([], time: 2, settings: s)
    _ = e.process(pair(0.9,0.9), time: 3, settings: s)
    #expect(e.process(pair(0.9,0.6)+[p(0.7,0.6,3)], time: 3.1, settings: s).isEmpty)
    #expect(!e.capturesScroll)
}
@Test func fineControlSwapAndQuarter() {
    var s = GestureSettings(); s.swapSides = true; s.bottomQuarterOnly = true
    var e = fresh(s)
    _ = e.process(pair(0.02,0.4), time: 1, settings: s)
    #expect(e.process(pair(0.02,0.6), time: 1.1, settings: s).isEmpty)
    _ = e.process([], time: 1.2, settings: s)
    _ = e.process(pair(0.02,0.10), time: 2, settings: s)
    guard case .volume(let amount) = e.process(pair(0.02,0.20), time: 2.1, settings: s, precise: true).first else { Issue.record("Expected volume"); return }
    #expect(abs(amount-0.0375) < 0.0001)
}
@Test func modifierAndGlobalOffCancelAllActions() {
    let s = GestureSettings(); var e = fresh()
    _ = e.process(pair(0.98,0.4), time: 1, settings: s)
    #expect(e.process(pair(0.98,0.6), time: 1.1, settings: s, modifierSatisfied: false).isEmpty)
    #expect(!e.capturesScroll)
    var off = s; off.enabled = false
    #expect(e.process(pair(0.98,0.8), time: 1.2, settings: off).isEmpty)
}
@Test func reversingSwipeClosesControlCenterWithoutLifting() {
    let s = GestureSettings(); var e = fresh()
    _ = e.process(pair(0.88,0.9), time: 1, settings: s)
    #expect(e.process(pair(0.88,0.7), time: 1.1, settings: s) == [.openControlCenter])
    #expect(e.process(pair(0.88,0.5), time: 1.2, settings: s).isEmpty)
    #expect(e.process(pair(0.88,0.65), time: 1.3, settings: s) == [.closeControlCenter])
    #expect(e.process(pair(0.88,0.85), time: 1.4, settings: s).isEmpty)
}
@Test func freshUpwardSwipeClosesControlCenter() {
    let s = GestureSettings(); var e = fresh()
    _ = e.process(pair(0.88,0.65), time: 1, settings: s)
    #expect(e.process(pair(0.88,0.85), time: 1.1, settings: s, controlCenterOpen: true) == [.closeControlCenter])
    #expect(e.process([], time: 1.2, settings: s).isEmpty)
}

@Test func upwardScrollWhenCenterClosedIsUntouched() {
    let s = GestureSettings(); var e = fresh()
    _ = e.process(pair(0.88,0.65), time: 1, settings: s)
    #expect(!e.capturesScroll && !e.capturesPointer)
    #expect(e.process(pair(0.88,0.85), time: 1.1, settings: s).isEmpty)
    #expect(!e.capturesScroll)
}
@Test func saturatedLevelsNeverRepeatHaptics() {
    #expect(!LevelFeedback.shouldTick(from: 1, to: 1))
    #expect(!LevelFeedback.shouldTick(from: 0, to: 0))
    #expect(!LevelFeedback.shouldTick(from: 0.511, to: 0.512))
    #expect(LevelFeedback.shouldTick(from: 0.99, to: 1))
    #expect(LevelFeedback.shouldTick(from: 0.01, to: 0))
    #expect(LevelFeedback.shouldTick(from: 0.54, to: 0.56))
    #expect(LevelFeedback.shouldTick(from: 1, to: 0.99))
}
