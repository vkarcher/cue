import SwiftUI

struct DiagnosticView: View {
    let status: NetworkServiceStatus
    let television: TelevisionControl

    var body: some View {
        Form {
            Section("Television") {
                TelevisionPicker(television: television, placeholder: "None")
                LabeledContent("Pairing", value: television.isPaired ? String(localized: "paired") : String(localized: "not paired"))
                LabeledContent("MAC addresses", value: television.macAddresses.isEmpty
                    ? String(localized: "unknown")
                    : television.macAddresses.joined(separator: ", "))
                HStack {
                    Button("Pair again") { Task { await television.pair() } }.disabled(television.serviceName == nil)
                    Button("Test input switch") { Task { await television.switchToLaunchInput() } }.disabled(!television.isPaired)
                    Button("Test power off") { Task { await television.turnOff() } }.disabled(!television.isPaired)
                }
            }

            LogSection(title: "Network service", text: status.daemonLog)
            LogSection(title: "Television", text: television.journal.joined(separator: "\n"))
        }
        .formStyle(.grouped)
        .navigationTitle("Diagnostics")
        .navigationSubtitle(String(localized: "pairing and logs"))
        .polling(every: .seconds(2)) { status.readLog() }
    }
}
