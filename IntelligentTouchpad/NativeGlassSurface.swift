import SwiftUI
import AppKit

/// Uses the OS renderer without extra blur, tint, borders, or shadow layers.
struct NativeGlassSurface: NSViewRepresentable {
    var radius: CGFloat = 29
    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .clear
            glass.cornerRadius = radius
            glass.contentView = NSView()
            return glass
        }
        let fallback = NSVisualEffectView()
        fallback.material = .popover
        fallback.state = .active
        return fallback
    }
    func updateNSView(_ view: NSView, context: Context) {
        if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
            glass.cornerRadius = radius
        }
    }
}

/// NSGlassEffectView owns its content, as required by AppKit's native API.
@available(macOS 26.0, *)
struct NativeGlassContainer<Content: View>: NSViewRepresentable {
    var radius: CGFloat = 29
    var content: Content
    init(radius: CGFloat = 29, @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.content = content()
    }
    func makeNSView(context: Context) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.style = .clear
        glass.cornerRadius = radius
        glass.contentView = NSHostingView(rootView: content)
        return glass
    }
    func updateNSView(_ glass: NSGlassEffectView, context: Context) {
        glass.cornerRadius = radius
        (glass.contentView as? NSHostingView<Content>)?.rootView = content
    }
}
