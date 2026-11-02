import AppKit
import QuartzCore

@MainActor final class HUDController {
    private var panel: NSPanel?
    private let content = NSView()
    private let icon = NSImageView()
    private let percentage = NSTextField(labelWithString: "")
    private let track = CALayer()
    private let fill = CALayer()
    private var dismissal: DispatchWorkItem?
    private var retirement: DispatchWorkItem?
    private var shown = false
    private var finishing = false
    private var lastSymbol = ""
    private let height: CGFloat = 56

    func show(symbol: String, value: Double, duration: Double = 0.8) {
        if panel == nil { createPanel() }
        guard let panel else { return }
        dismissal?.cancel(); retirement?.cancel()
        finishing = false
        if symbol != lastSymbol {
            icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol == "sun.max.fill" ? "Brightness" : "Volume")
            lastSymbol = symbol
        }
        let level = min(1, max(0, value))
        let text = "%\(Int((level*100).rounded()))"
        if percentage.stringValue != text { percentage.stringValue = text }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        fill.frame.size.width = track.bounds.width * level
        CATransaction.commit()
        if !shown {
            if !panel.isVisible {
                let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
                if let screen {
                    var width: CGFloat = 260
                    if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                        width = max(220, right.minX-left.maxX)
                    }
                    panel.setFrame(NSRect(x: screen.frame.midX-width/2,
                                          y: screen.frame.maxY-screen.safeAreaInsets.top-height,
                                          width: width, height: height), display: false)
                    layout(width: width)
                }
                content.layer?.transform = CATransform3DMakeTranslation(0, height, 0)
                panel.orderFrontRegardless()
            }
            shown = true
            slide(to: 0)
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        fill.frame = CGRect(x: 0, y: 0, width: track.bounds.width*level, height: 4)
        CATransaction.commit()
        scheduleDismiss(after: duration)
    }
    func endInteraction() {
        guard shown, !finishing else { return }
        finishing = true
        scheduleDismiss(after: 0.18)
    }
    private func scheduleDismiss(after delay: Double) {
        dismissal?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.shown = false
            self.slide(to: self.height)
            let retire = DispatchWorkItem { [weak self] in
                guard let self, !self.shown else { return }
                self.panel?.orderOut(nil)
            }
            self.retirement = retire
            DispatchQueue.main.asyncAfter(deadline: .now()+0.2, execute: retire)
        }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now()+delay, execute: work)
    }
    private func slide(to y: CGFloat) {
        guard let layer = content.layer else { return }
        let start = layer.presentation()?.transform ?? layer.transform
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.transform = CATransform3DMakeTranslation(0, y, 0)
        CATransaction.commit()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: start)
        animation.toValue = NSValue(caTransform3D: layer.transform)
        animation.duration = 0.18
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "slide")
    }
    private func createPanel() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = false; panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let root = NSView()
        root.wantsLayer = true
        root.layer?.masksToBounds = true
        panel.contentView = root
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.cgColor
        content.layer?.cornerRadius = 16
        content.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        root.addSubview(content)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        icon.contentTintColor = .white
        percentage.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        percentage.textColor = .white; percentage.alignment = .right
        content.addSubview(icon); content.addSubview(percentage)
        track.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
        track.cornerRadius = 2
        fill.backgroundColor = NSColor.white.cgColor; fill.cornerRadius = 2
        track.addSublayer(fill); content.layer?.addSublayer(track)
        self.panel = panel
        layout(width: 260)
    }
    private func layout(width: CGFloat) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        content.frame = NSRect(x: 0, y: 0, width: width, height: height)
        icon.frame = NSRect(x: 18, y: 18, width: 20, height: 20)
        percentage.frame = NSRect(x: width-56, y: 19, width: 38, height: 18)
        track.frame = CGRect(x: 50, y: 26, width: width-120, height: 4)
        fill.frame = track.bounds
        CATransaction.commit()
    }
}
