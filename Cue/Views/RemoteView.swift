import SwiftUI

struct RemoteView: View {
    let television: TelevisionControl
    @FocusState private var hasKeyboardFocus: Bool

    private var isOn: Bool { television.power == .on }

    var body: some View {
        Group {
            if television.isPaired {
                remote
            } else {
                PairingView(television: television)
            }
        }
        .navigationTitle("Remote")
        .navigationSubtitle(subtitle)
        .toolbar {
            if television.isPaired {
                ToolbarItem(placement: .primaryAction) { powerButton }
            }
        }
        .polling(every: .seconds(5), id: television.clientKey) { await television.refresh() }
    }

    private var remote: some View {
        ScrollView {
            VStack(spacing: 14) {
                inputs
                Touchpad(isActive: isOn) { television.press($0) }
            }
            .padding(20)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) { controls }
        .focusable()
        .focused($hasKeyboardFocus)
        .focusEffectDisabled()
        .onKeyPress(action: handle)
        .onAppear { hasKeyboardFocus = true }
    }

    private var subtitle: String {
        guard television.isPaired else { return String(localized: "no television") }
        switch television.power {
        case .on: return String(localized: "\(television.model) · on")
        case .off: return String(localized: "\(television.model) · off")
        case .unknown: return String(localized: "\(television.model) · connecting…")
        }
    }

    /// The only tinted control: green to turn the television on, red to turn it off.
    private var powerButton: some View {
        Button {
            Task { await television.togglePower() }
        } label: {
            Label(isOn ? String(localized: "Turn the television off") : String(localized: "Turn the television on"), systemImage: "power")
        }
        .buttonStyle(.glassProminent)
        .tint(isOn ? .red : .green)
        .help(isOn ? String(localized: "Turn the television off") : String(localized: "Turn the television on"))
    }

    private var inputs: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(television.inputs) { input in
                Button { television.switchInput(to: input.id) } label: {
                    SourceTile(
                        input: input,
                        symbol: symbol(for: input),
                        isLaunchInput: input.id == television.launchInput,
                        isSelected: isOn && input.id == television.currentInput
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isOn)
            }
        }
        .opacity(isOn ? 1 : 0.5)
    }

    private func symbol(for input: TelevisionControl.Input) -> String {
        if input.id == television.launchInput { return "gamecontroller" }
        return input.label.localizedCaseInsensitiveContains("apple") ? "appletv" : "cable.connector.horizontal"
    }

    /// Floating glass bar: the buttons on it are plain, since glass never sits on glass.
    private var controls: some View {
        HStack(spacing: 16) {
            Button { television.press(.back) } label: { Image(systemName: "chevron.backward") }
                .help("Back (Esc)")
            Button { television.press(.home) } label: { Image(systemName: "house") }
                .help("Home")
            Button { television.playPause() } label: { Image(systemName: "playpause") }
                .help("Play / pause (space)")
            Divider().frame(height: 18)
            Button { television.toggleMute() } label: {
                Image(systemName: television.isMuted ? "speaker.slash.fill" : "speaker.wave.2")
            }
            .help("Mute")
            Slider(
                value: Binding(get: { Double(television.volume) }, set: { television.volume = Int($0) }),
                in: 0...100
            ) { editing in
                if !editing { television.setVolume(television.volume) }
            }
            .frame(width: 180)
            Text("\(television.volume)").monospacedDigit().foregroundStyle(.secondary).frame(width: 26, alignment: .trailing)
        }
        .buttonStyle(.borderless)
        .font(.title3)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, 16)
        .disabled(!isOn)
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard isOn else { return .ignored }
        switch press.key {
        case .upArrow: television.press(.up)
        case .downArrow: television.press(.down)
        case .leftArrow: television.press(.left)
        case .rightArrow: television.press(.right)
        case .return: television.press(.enter)
        case .escape: television.press(.back)
        case .space: television.playPause()
        default:
            switch press.characters {
            case "+", "=": television.setVolume(min(100, television.volume + 1))
            case "-": television.setVolume(max(0, television.volume - 1))
            default: return .ignored
            }
        }
        return .handled
    }
}

private struct SourceTile: View {
    let input: TelevisionControl.Input
    let symbol: String
    let isLaunchInput: Bool
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: symbol).font(.title2)
            VStack(alignment: .leading, spacing: 1) {
                Text(input.label).font(.callout.weight(.semibold)).lineLimit(1)
                Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(12)
        .background(isSelected ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.fill.quaternary), in: .rect(cornerRadius: 14))
        .overlay {
            if isSelected { RoundedRectangle(cornerRadius: 14).strokeBorder(.tint, lineWidth: 1.5) }
        }
        .contentShape(.rect(cornerRadius: 14))
    }

    private var caption: String {
        if isLaunchInput { return String(localized: "\(input.port) · game") }
        return input.label == input.port ? " " : input.port
    }
}

private struct Touchpad: View {
    private static let shortcuts: [LocalizedStringResource] = ["← ↑ → ↓", "⏎ OK", "⎋ Back", "space ⏯", "+ − volume"]

    let isActive: Bool
    let press: (RemoteButton) -> Void
    @State private var tracker = SwipeTracker()

    var body: some View {
        RoundedRectangle(cornerRadius: 22)
            .fill(.fill.quaternary)
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: isActive ? "hand.draw" : "power").font(.largeTitle).foregroundStyle(.tertiary)
                    Text(isActive ? String(localized: "Swipe to navigate · click to select") : String(localized: "The television is off"))
                        .font(.callout).foregroundStyle(.secondary)
                    if isActive {
                        HStack(spacing: 6) {
                            ForEach(Self.shortcuts, id: \.key) { shortcut in
                                Text(shortcut).font(.caption.monospaced())
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(.fill.tertiary, in: .rect(cornerRadius: 5))
                            }
                        }
                    }
                }
            }
            .frame(height: 260)
            .contentShape(.rect(cornerRadius: 22))
            .gesture(isActive ? swipe : nil)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if let button = tracker.move(to: value.translation) { press(button) }
            }
            .onEnded { value in
                if let button = tracker.end(at: value.translation) { press(button) }
            }
    }
}

private struct PairingView: View {
    let television: TelevisionControl

    var body: some View {
        ContentUnavailableView {
            Label("No television paired", systemImage: "tv")
        } description: {
            if television.choices.isEmpty {
                Text("No LG television found on the network.")
            } else {
                Text("Choose your LG television, then accept the request shown on screen.")
            }
        } actions: {
            if !television.choices.isEmpty {
                HStack {
                    TelevisionPicker(television: television, placeholder: "Choose…")
                        .labelsHidden()
                        .fixedSize()
                    Button("Pair") { Task { await television.pair() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(television.serviceName == nil)
                }
            }
            if let last = television.journal.last {
                Text(last).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
    }
}
