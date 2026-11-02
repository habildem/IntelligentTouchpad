import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences
    @State private var settings = false
    @State private var guide = false
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !model.ready { permissionCard }
                    if let issue = model.issue {
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                    if settings { settingsContent } else { mainContent }
                }.padding(20)
            }
            Divider()
            HStack {
                Button { settings.toggle() } label: {
                    Label(settings ? "Controls" : "Settings", systemImage: settings ? "chevron.left" : "slider.horizontal.3")
                }.buttonStyle(.plain)
                Spacer()
                Button { guide = true } label: { Image(systemName: "questionmark.circle") }
                    .buttonStyle(.plain).help("User guide").accessibilityLabel("User guide")
                Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }
                    .buttonStyle(.plain).help("Quit IntelligentTouchpad").accessibilityLabel("Quit IntelligentTouchpad")
            }.font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 380, height: 720)
        .background(NativeGlassSurface(radius: 16))
        .preferredColorScheme(preferences.colorScheme)
        .onAppear { model.panelVisible = true; model.refresh() }
        .onDisappear { model.panelVisible = false }
        .sheet(isPresented: $guide) { guideContent }
    }
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.draw").font(.system(size: 21, weight: .medium)).foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 3) {
                Text(settings ? "Settings" : "IntelligentTouchpad").font(.system(size: 15, weight: .semibold))
                HStack(spacing: 5) {
                    Circle().fill(model.ready && preferences.gestures.enabled ? Color.green : Color.orange).frame(width: 5, height: 5)
                    Text(model.status).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("All gestures", isOn: $preferences.gestures.enabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                .help("Enable or pause all gestures")
        }.padding(20)
    }
    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(model.trusted ? "Trackpad connection" : "Accessibility permission required", systemImage: model.trusted ? "hand.point.up.left" : "lock.open")
                .font(.system(size: 13, weight: .semibold))
            Text(model.trusted ? model.deviceStatus : "Grant Accessibility permission to use edge gestures and open Control Center. Touches are processed on this Mac.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                if !model.trusted {
                    Button("Open System Settings") { model.requestPermission() }.buttonStyle(.borderedProminent).tint(.teal)
                }
                Button("Try again") { model.refresh(reconnect: true) }.buttonStyle(.bordered)
            }.controlSize(.small)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }
    private var mainContent: some View {
        VStack(spacing: 18) {
            TrackpadMap(settings: preferences.gestures, volume: model.volume, brightness: model.brightness, points: model.touchPoints)
            VStack(spacing: 0) {
                feature("Left edge", subtitle: preferences.gestures.swapSides ? "Slide with two fingers to adjust volume" : "Slide with two fingers to adjust brightness",
                        symbol: preferences.gestures.swapSides ? "speaker.wave.2" : "sun.max", color: preferences.gestures.swapSides ? .blue : .orange, value: $preferences.gestures.leftEnabled)
                feature("Right edge", subtitle: preferences.gestures.swapSides ? "Slide with two fingers to adjust brightness" : "Slide with two fingers to adjust volume",
                        symbol: preferences.gestures.swapSides ? "sun.max" : "speaker.wave.2", color: preferences.gestures.swapSides ? .orange : .blue, value: $preferences.gestures.rightEnabled)
                Divider().padding(.vertical, 8)
                feature("Control Center", subtitle: "Swipe down with two fingers to open, up to close",
                        symbol: "switch.2", color: .teal, value: $preferences.gestures.controlCenterEnabled)
                feature("Quick mute", subtitle: "Double-tap the top-right corner with two fingers",
                        symbol: "speaker.slash", color: .secondary, value: $preferences.gestures.muteEnabled)
                feature("Skip track", subtitle: "Swipe along the bottom edge with two fingers",
                        symbol: "forward.end", color: .secondary, value: $preferences.gestures.mediaSwipeEnabled)
                feature("Play / pause", subtitle: "Tap the bottom edge with two fingers",
                        symbol: "playpause", color: .secondary, value: $preferences.gestures.mediaTapEnabled)
            }

        }
    }
    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Gesture area")
            VStack(spacing: 0) {
                feature("Swap sides", subtitle: "Swap volume and brightness", symbol: "arrow.left.arrow.right", value: $preferences.gestures.swapSides)
                feature("Bottom quarter only", subtitle: "Use the bottom 25% of the left and right edges", symbol: "rectangle.bottomthird.inset.filled", value: $preferences.gestures.bottomQuarterOnly)
            }
            slider("Edge width", value: $preferences.gestures.edgeWidth, range: 0.03...0.15,
                   detail: String(format: "%%%d", Int(preferences.gestures.edgeWidth*100)))
            slider("Sensitivity", value: $preferences.gestures.sensitivity, range: 0.5...3,
                   detail: String(format: "%.1f×", preferences.gestures.sensitivity))
            Picker("Required modifier", selection: $preferences.gestures.modifier) {
                Text("None").tag(GestureSettings.Modifier.none)
                Text("Option ⌥").tag(GestureSettings.Modifier.option)
                Text("Fn").tag(GestureSettings.Modifier.fn)
            }.pickerStyle(.menu).font(.system(size: 12))
            Divider()
            sectionTitle("While sliding")
            VStack(spacing: 0) {
                feature("Freeze cursor", subtitle: "After an edge slide is detected", symbol: "cursorarrow", value: $preferences.gestures.freezeCursor)
                feature("Fine control", subtitle: "Hold Shift + Option for quarter speed", symbol: "dial.low", value: $preferences.gestures.fineControl)
                feature("Haptic feedback", subtitle: "Light tick on supported trackpads", symbol: "waveform", value: $preferences.gestures.haptics)
                feature("On-screen display", subtitle: "Show volume and brightness changes", symbol: "rectangle.on.rectangle", value: $preferences.gestures.showHUD)
            }
            Divider()
            sectionTitle("General")
            Picker("Appearance", selection: $preferences.gestures.appearance) {
                Text("System").tag(GestureSettings.Appearance.system)
                Text("Light").tag(GestureSettings.Appearance.light)
                Text("Dark").tag(GestureSettings.Appearance.dark)
            }.pickerStyle(.segmented)
            Toggle("Open at login", isOn: Binding(get: { model.loginEnabled }, set: model.setLogin)).toggleStyle(.switch).controlSize(.small)
            Text(model.deviceStatus).font(.caption).foregroundStyle(.secondary)
            Text("Brightness controls the built-in display. The top-right gesture opens Wi-Fi and Bluetooth controls. Media commands are handled by the active player.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Reconnect trackpad") { model.refresh(reconnect: true) }.controlSize(.small)
        }
    }
    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
    }
    private func feature(_ title: String, subtitle: String, symbol: String, color: Color = .secondary, value: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(color).frame(width: 25)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(.teal)
        }.padding(.vertical, 8)
    }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, detail: String) -> some View {
        VStack(spacing: 7) {
            HStack { Text(title); Spacer(); Text(detail).monospacedDigit().foregroundStyle(.secondary) }.font(.system(size: 12))
            Slider(value: value, in: range).tint(.teal).accessibilityLabel(title)
        }
    }
    private var guideContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your edges, your controls.").font(.title2.weight(.semibold))
            Text("Place two fingers at an edge of the trackpad, then slide. Gestures starting in the center work normally.")
            Label(preferences.gestures.swapSides ? "Left: volume · Right: brightness" : "Left: brightness · Right: volume", systemImage: "arrow.up.arrow.down")
            Label("Bottom: skip tracks", systemImage: "arrow.left.arrow.right")
            Label("Top right: double-tap with two fingers to mute", systemImage: "speaker.slash")
            Label("Top right: swipe down with two fingers to open Control Center, up to close", systemImage: "switch.2")
            Text("Turn off any feature in the main panel. If gestures trigger accidentally, narrow the edges or require Option in Settings.").foregroundStyle(.secondary)
            Button("Got it") { guide = false }.buttonStyle(.borderedProminent).tint(.teal).keyboardShortcut(.defaultAction)
        }.font(.system(size: 13)).padding(28).frame(width: 360)
    }
}

private struct TrackpadMap: View {
    let settings: GestureSettings
    let volume: Double?
    let brightness: Double?
    let points: [TouchPoint]
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.045))
                RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                HStack {
                    level(symbol: settings.swapSides ? "speaker.wave.2.fill" : "sun.max.fill",
                          value: settings.swapSides ? volume : brightness,
                          enabled: settings.leftEnabled, color: settings.swapSides ? .blue : .orange)
                    Spacer()
                    level(symbol: settings.swapSides ? "sun.max.fill" : "speaker.wave.2.fill",
                          value: settings.swapSides ? brightness : volume,
                          enabled: settings.rightEnabled, color: settings.swapSides ? .orange : .blue)
                }.padding(.horizontal, 24)
                HStack(alignment: .bottom) {
                    Capsule().fill(settings.leftEnabled && settings.enabled ? (settings.swapSides ? Color.blue : Color.orange) : Color.secondary.opacity(0.2)).frame(width: 4, height: settings.bottomQuarterOnly ? 24 : 96)
                    Spacer()
                    Capsule().fill(settings.rightEnabled && settings.enabled ? (settings.swapSides ? Color.orange : Color.blue) : Color.secondary.opacity(0.2)).frame(width: 4, height: settings.bottomQuarterOnly ? 24 : 96)
                }.frame(maxHeight: .infinity, alignment: .bottom).padding(.horizontal, 10).padding(.vertical, 22)
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.down").font(.system(size: 10, weight: .bold))
                        Image(systemName: "switch.2").font(.system(size: 13))
                    }.foregroundStyle(settings.controlCenterEnabled && settings.enabled ? Color.teal : Color.secondary.opacity(0.3))
                    Spacer()
                    HStack(spacing: 13) {
                        Image(systemName: "backward.end.fill").opacity(settings.mediaSwipeEnabled && settings.enabled ? 1 : 0.25)
                        Image(systemName: "playpause.fill").opacity(settings.mediaTapEnabled && settings.enabled ? 1 : 0.25)
                        Image(systemName: "forward.end.fill").opacity(settings.mediaSwipeEnabled && settings.enabled ? 1 : 0.25)
                    }.font(.system(size: 9)).foregroundStyle(.secondary)
                }.padding(.horizontal, 22).padding(.vertical, 11)
                ForEach(points, id: \.id) { point in
                    Circle().fill(.teal.opacity(0.6)).frame(width: 13, height: 13)
                        .position(x: point.x*size.width, y: (1-point.y)*size.height)
                }
            }
        }.frame(height: 140)
            .accessibilityElement(children: .combine).accessibilityLabel("Trackpad regions")
    }
    private func level(symbol: String, value: Double?, enabled: Bool, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(color)
            if !enabled || !settings.enabled { Text("Off").font(.system(size: 19, weight: .light)) }
            else if let value {
                Text(value, format: .percent.precision(.fractionLength(0))).font(.system(size: 30, weight: .light)).monospacedDigit()
            } else { Text("—").font(.system(size: 30, weight: .light)).accessibilityLabel("Value unavailable") }
        }.opacity(enabled && settings.enabled ? 1 : 0.45)
    }
}
