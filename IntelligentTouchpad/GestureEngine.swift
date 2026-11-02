import Foundation

nonisolated struct TouchPoint: Sendable, Equatable {
    var id: Int
    var x: Double
    var y: Double // bottom = 0, top = 1
}

nonisolated struct GestureSettings: Codable, Equatable, Sendable {
    var enabled = true
    var leftEnabled = true
    var rightEnabled = true
    var muteEnabled = true
    var mediaSwipeEnabled = true
    var mediaTapEnabled = false
    var controlCenterEnabled = true
    var swapSides = false
    var bottomQuarterOnly = false
    var freezeCursor = true
    var fineControl = true
    var haptics = true
    var showHUD = true
    var sensitivity = 1.5
    var edgeWidth = 0.07
    var modifier = Modifier.none
    var appearance = Appearance.system
    enum Modifier: String, Codable, CaseIterable, Sendable { case none, option, fn }
    enum Appearance: String, Codable, CaseIterable, Sendable { case system, light, dark }
}

nonisolated enum GestureAction: Equatable, Sendable {
    case volume(Double), brightness(Double), mute, nextTrack, previousTrack, playPause, openControlCenter, closeControlCenter
}

/// Two-finger recognizer. Region is chosen at the initial contact, then locked.
/// A lone finger only waits briefly for its partner and never produces an action.
nonisolated struct GestureEngine {
    enum Region { case left, right, bottom, corner, pending, ignored }
    struct Session {
        var region: Region
        var ids: Set<Int>
        var origin: TouchPoint
        var last: TouchPoint
        var began: Double
        var maxDistance = 0.0
        var activated = false
        var fired = false
        var releasing = false
        var openedCenter = false
        var lowestY = 1.0
        var closedCenter = false
    }
    private var session: Session?
    private var lastCornerTap: (time: Double, point: TouchPoint)?
    private var previousSettings: GestureSettings?
    private(set) var capturesPointer = false
    private(set) var capturesScroll = false

    mutating func reset() {
        session = nil; lastCornerTap = nil
        capturesPointer = false; capturesScroll = false
    }
    mutating func process(_ points: [TouchPoint], time: Double, settings s: GestureSettings,
                          modifierSatisfied: Bool = true, precise: Bool = false, mouseDown: Bool = false, controlCenterOpen: Bool = false) -> [GestureAction] {
        if previousSettings != s {
            reset(); previousSettings = s
            if !points.isEmpty { session = makeSession(.ignored, points, time) }
        }
        guard s.enabled, modifierSatisfied, !mouseDown else {
            reset()
            if !points.isEmpty { session = makeSession(.ignored, points, time) }
            return []
        }
        if points.isEmpty {
            defer { session = nil; capturesPointer = false; capturesScroll = false }
            guard let current = session, !current.fired, !current.activated,
                  current.maxDistance < 0.025, time-current.began < 0.3 else { return [] }
            if current.region == .corner, current.origin.y >= 0.72, s.muteEnabled {
                if let tap = lastCornerTap, time-tap.time < 0.4,
                   hypot(tap.point.x-current.origin.x, tap.point.y-current.origin.y) < 0.12 {
                    lastCornerTap = nil; return [.mute]
                }
                lastCornerTap = (time, current.origin)
            } else if current.region == .bottom, s.mediaTapEnabled { return [.playPause] }
            return []
        }
        guard points.count <= 2, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else {
            session = makeSession(.ignored, points, time)
            capturesPointer = false; capturesScroll = false; return []
        }
        if session == nil {
            let region = points.count == 1 ? Region.pending : region(for: points, settings: s)
            session = makeSession(region, points, time)
            capture(region, settings: s)
            if region == .corner && !controlCenterOpen { capturesScroll = false; capturesPointer = false }
            return []
        }
        guard var current = session else { return [] }
        if current.region == .ignored { return [] }
        let ids = Set(points.map(\.id))
        let center = centroid(points)
        if current.region == .pending {
            let moved = hypot(center.x-current.origin.x, center.y-current.origin.y)
            if points.count == 2, time-current.began <= 0.18, current.ids.isSubset(of: ids),
               current.maxDistance < 0.025 {
                let chosen = region(for: points, settings: s)
                // The first contact itself must already be in the chosen region.
                let start = current.origin
                let startsInRegion: Bool
                switch chosen {
                case .left: startsInRegion = start.x <= s.edgeWidth+0.16
                case .right: startsInRegion = start.x >= 1-s.edgeWidth-0.16
                case .bottom: startsInRegion = start.y <= s.edgeWidth+0.15
                case .corner: startsInRegion = start.x >= 0.72 && start.y >= 0.60
                case .pending, .ignored: startsInRegion = false
                }
                let accepted = startsInRegion ? chosen : .ignored
                session = makeSession(accepted, points, time)
                capture(accepted, settings: s)
                if accepted == .corner && !controlCenterOpen { capturesScroll = false; capturesPointer = false }
            } else if time-current.began > 0.18 || moved > 0.025 {
                session = makeSession(.ignored, points, time)
            } else { current.maxDistance = max(current.maxDistance, moved); session = current }
            return []
        }
        if points.count == 1, ids.isSubset(of: current.ids) {
            current.releasing = true; session = current
            capturesPointer = false; capturesScroll = false
            return []
        }
        guard points.count == 2, ids == current.ids, !current.releasing else {
            session = makeSession(.ignored, points, time)
            capturesPointer = false; capturesScroll = false; return []
        }
        let dx = center.x-current.origin.x, dy = center.y-current.origin.y
        current.maxDistance = max(current.maxDistance, hypot(dx,dy))
        defer { current.last = center; session = current }
        if current.region == .corner, current.openedCenter, !current.closedCenter {
            current.lowestY = min(current.lowestY, center.y)
            if center.y-current.lowestY > 0.10 {
                current.closedCenter = true
                return [.closeControlCenter]
            }
        }
        guard !current.fired else { return [] }
        switch current.region {
        case .corner:
            if s.controlCenterEnabled, current.origin.y >= 0.72, dy < -0.10, abs(dy) > abs(dx)*1.4 {
                current.fired = true; current.openedCenter = true; current.lowestY = center.y
                capturesScroll = true; capturesPointer = s.freezeCursor
                return [.openControlCenter]
            }
            if s.controlCenterEnabled, controlCenterOpen, dy > 0.10, abs(dy) > abs(dx)*1.4 {
                current.fired = true; current.closedCenter = true
                return [.closeControlCenter]
            }
        case .left, .right:
            guard current.activated || (abs(dy) > 0.018 && abs(dy) > abs(dx)*1.4) else { return [] }
            let delta = (current.activated ? center.y-current.last.y : dy) * s.sensitivity * (s.fineControl && precise ? 0.25 : 1)
            current.activated = true
            capturesPointer = s.freezeCursor
            let volume = (current.region == .right) != s.swapSides
            return [volume ? .volume(delta) : .brightness(delta)]
        case .bottom:
            if s.mediaSwipeEnabled && abs(dx) > 0.12 && abs(dx) > abs(dy)*1.5 {
                current.fired = true; return [dx > 0 ? .nextTrack : .previousTrack]
            }
        case .pending, .ignored: break
        }
        return []
    }
    private func region(for points: [TouchPoint], settings s: GestureSettings) -> Region {
        guard points.count == 2 else { return .ignored }
        let center = centroid(points)
        if (s.controlCenterEnabled || s.muteEnabled), points.allSatisfy({ $0.x >= 0.72 && $0.y >= 0.60 }) { return .corner }
        if (s.mediaSwipeEnabled || s.mediaTapEnabled), points.contains(where: { $0.y <= s.edgeWidth }),
           points.allSatisfy({ $0.y <= s.edgeWidth+0.15 }) { return .bottom }
        guard !s.bottomQuarterOnly || points.allSatisfy({ $0.y <= 0.25 }) else { return .ignored }
        if s.leftEnabled, points.contains(where: { $0.x <= s.edgeWidth }), center.x <= s.edgeWidth+0.08 { return .left }
        if s.rightEnabled, points.contains(where: { $0.x >= 1-s.edgeWidth }), center.x >= 1-s.edgeWidth-0.08 { return .right }
        return .ignored
    }
    private func centroid(_ points: [TouchPoint]) -> TouchPoint {
        guard !points.isEmpty else { return TouchPoint(id: 0, x: 0, y: 0) }
        return TouchPoint(id: 0, x: points.map(\.x).reduce(0,+)/Double(points.count), y: points.map(\.y).reduce(0,+)/Double(points.count))
    }
    private func makeSession(_ region: Region, _ points: [TouchPoint], _ time: Double) -> Session {
        let center = centroid(points)
        return Session(region: region, ids: Set(points.map(\.id)), origin: center, last: center, began: time)
    }
    private mutating func capture(_ region: Region, settings: GestureSettings) {
        capturesScroll = region != .ignored && region != .pending
        capturesPointer = capturesScroll && settings.freezeCursor
    }
}

/// Feedback follows real output changes, not incoming touch frames.
nonisolated enum LevelFeedback {
    static func shouldTick(from previous: Double?, to value: Double) -> Bool {
        guard let previous, previous.isFinite, value.isFinite,
              abs(value-previous) > 0.0001 else { return false }
        // One meaningful tick per 5% boundary, including arrival at either limit.
        return Int((previous*20).rounded(.down)) != Int((value*20).rounded(.down)) ||
            (value == 0 && previous > 0) || (value == 1 && previous < 1)
    }
}
