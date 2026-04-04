import SwiftUI
import AVFoundation

/// Settings window: API key, custom dictionary, preferences.
struct SettingsView: View {
    @AppStorage("openaiApiKey") private var apiKey = ""
    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    @State private var newWord = ""

    var body: some View {
        Form {
            Section("OpenAI API Key") {
                SecureField("sk-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                Text("Uses gpt-4o-transcribe for real-time transcription")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Custom Dictionary") {
                HStack {
                    TextField("Add word...", text: $newWord)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addWord() }
                    Button("Add") { addWord() }
                        .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                FlowLayout(spacing: 6) {
                    ForEach(Array(CustomDictionary.words.enumerated()), id: \.offset) { index, word in
                        HStack(spacing: 4) {
                            Text(word)
                                .font(.caption)
                            Button(action: { CustomDictionary.remove(at: index) }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }
            }

            Section("System") {
                Toggle("Sound feedback", isOn: $soundEnabled)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LaunchAtLogin.set(enabled: newValue)
                    }
            }

            Section("Permissions") {
                PermissionRow(
                    title: "Microphone",
                    granted: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                )
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 500)
    }

    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        CustomDictionary.add(trimmed)
        newWord = ""
    }
}

private struct PermissionRow: View {
    let title: String
    let granted: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else {
                Label("Not Granted", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }
}

// MARK: - Flow Layout (tag cloud)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(in: proposal.width ?? 0, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x)
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
