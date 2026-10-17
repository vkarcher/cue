import SwiftUI

enum Destination: CaseIterable, Identifiable {
    case remote, session, diagnostics

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .remote: "Remote"
        case .session: "Game session"
        case .diagnostics: "Diagnostics"
        }
    }

    var symbol: String {
        switch self {
        case .remote: "appletvremote.gen4"
        case .session: "gamecontroller"
        case .diagnostics: "stethoscope"
        }
    }
}

struct MainWindow: View {
    let status: NetworkServiceStatus
    let television: TelevisionControl
    @State private var destination: Destination? = .remote

    var body: some View {
        NavigationSplitView {
            List(Destination.allCases, selection: $destination) { destination in
                Label { Text(destination.title) } icon: { Image(systemName: destination.symbol) }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 6) {
                    Circle().fill(status.isSessionActive ? .green : .secondary).frame(width: 7, height: 7)
                    Text(status.summary).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .navigationSplitViewColumnWidth(200)
        } detail: {
            switch destination ?? .remote {
            case .remote: RemoteView(television: television)
            case .session: SessionView(status: status, television: television)
            case .diagnostics: DiagnosticView(status: status, television: television)
            }
        }
        .frame(minWidth: 860, minHeight: 640)
        // A regular app while the window is open, so it can take focus; back to the menu bar only when it closes.
        .onAppear {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate()
        }
        .onDisappear { NSApplication.shared.setActivationPolicy(.accessory) }
    }
}
