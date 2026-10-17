import ServiceManagement
import SwiftUI

struct SessionView: View {
    let status: NetworkServiceStatus
    @Bindable var television: TelevisionControl

    var body: some View {
        Form {
            Section {
                Toggle(isOn: status.isEnabledBinding) {
                    Text("Automatic activation")
                    Text("Starts when GeForce NOW launches and stops when it quits.")
                }
                .disabled(!status.isInstalled)
            }

            Section("During a game") {
                Label {
                    Text("AWDL off")
                    Text("Removes Wi-Fi latency spikes caused by AirDrop and Continuity.")
                } icon: {
                    Image(systemName: "wifi.slash")
                }
                Label {
                    Text("AirDrop set to No One")
                    Text("Nobody can send you a file during the game.")
                } icon: {
                    Image(systemName: "dot.radiowaves.left.and.right")
                }
            }

            Section("Television") {
                if television.isPaired {
                    Toggle(isOn: $television.switchesInputOnLaunch) {
                        Text("Switch input at launch")
                        Text("Turns the television on and shows this input when GeForce NOW starts.")
                    }
                    if television.switchesInputOnLaunch {
                        Picker("Input", selection: $television.launchInput) {
                            ForEach(television.inputs) { Text($0.label).tag($0.id) }
                        }
                    }
                    Toggle(isOn: $television.turnsOffOnQuit) {
                        Text("Turn off when quitting")
                        Text("Turns the television off when GeForce NOW quits.")
                    }
                } else {
                    Text("Pair a television from Remote.").foregroundStyle(.secondary)
                }
            }

            Section("Service") {
                installation
                Toggle("Open Cue at login", isOn: Binding(get: { status.opensAtLogin }, set: { status.setOpensAtLogin($0) }))
                if let error = status.lastError {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Game session")
        .navigationSubtitle(status.summary)
    }

    @ViewBuilder private var installation: some View {
        switch status.installation {
        case .installed:
            LabeledContent("Installed") {
                Button("Uninstall") { Task { await status.uninstall() } }
            }
        case .awaitingApproval:
            LabeledContent("Allow Cue in System Settings to finish the installation.") {
                Button("Open System Settings") { SMAppService.openSystemSettingsLoginItems() }
                    .buttonStyle(.borderedProminent)
            }
        case .notInstalled:
            LabeledContent("The service is not installed") {
                Button("Install") { status.install() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
