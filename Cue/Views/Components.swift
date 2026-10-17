import SwiftUI

struct TelevisionPicker: View {
    let television: TelevisionControl
    let placeholder: LocalizedStringKey

    var body: some View {
        Picker("Television", selection: Binding(get: { television.serviceName }, set: { television.select($0) })) {
            Text(placeholder).tag(String?.none)
            ForEach(television.choices, id: \.self) { Text($0).tag(String?.some($0)) }
        }
    }
}

/// A form section holding a scrollable log, with a copy button in its header.
struct LogSection: View {
    private static let end = "end"

    let title: LocalizedStringKey
    let text: String

    var body: some View {
        Section {
            // The newest entries are at the end: the log opens scrolled to them, the page around it does not.
            ScrollViewReader { proxy in
                ScrollView {
                    Text(text.isEmpty ? String(localized: "No entries") : text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(text.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(height: 0).id(Self.end)
                }
                .frame(height: 180)
                .onChange(of: text, initial: true) { proxy.scrollTo(Self.end) }
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .disabled(text.isEmpty)
            }
        }
    }
}

extension NetworkServiceStatus {
    var isEnabledBinding: Binding<Bool> {
        Binding(get: { self.isEnabled }, set: { self.setEnabled($0) })
    }
}

extension View {
    /// Runs `action` now, then every `interval`, for as long as the view is shown.
    func polling(every interval: Duration, _ action: @escaping @MainActor () async -> Void) -> some View {
        task { await repeating(every: interval, action) }
    }

    /// Restarts the polling whenever `id` changes.
    func polling(every interval: Duration, id: some Equatable, _ action: @escaping @MainActor () async -> Void) -> some View {
        task(id: id) { await repeating(every: interval, action) }
    }
}

@MainActor
private func repeating(every interval: Duration, _ action: @MainActor () async -> Void) async {
    while !Task.isCancelled {
        await action()
        try? await Task.sleep(for: interval)
    }
}
