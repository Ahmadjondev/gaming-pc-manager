import SwiftUI

public struct AlertSheet: View {
    public let station: Station
    @ObservedObject public var service: WebSocketService
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = "Admin Notice"
    @State private var message: String = ""

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Send Announcement: \(station.displayName)", systemImage: "megaphone.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.cyan)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Title")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.gray)
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Message")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.gray)
                TextEditor(text: $message)
                    .frame(height: 90)
                    .font(.system(size: 13))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
            }

            HStack {
                Spacer()
                Button("Send Message") {
                    guard !message.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    service.sendAlert(stationId: station.id, title: title, message: message)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .disabled(message.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 440)
    }
}
