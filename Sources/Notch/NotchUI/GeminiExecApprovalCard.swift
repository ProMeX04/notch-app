import AppKit
import NotchGeminiLiveCore
import SwiftUI

struct GeminiExecApprovalCard: View {
    let request: ExecApprovalRequest
    let queueCount: Int
    let onApproveOnce: () -> Void
    let onApproveExact: () -> Void
    let onApproveFamily: () -> Void
    let onDeny: () -> Void

    @AppStorage("app_language") private var appLanguage: String = "English"
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(nsColor: .systemOrange).ensureMinimumBrightness(factor: 0.75))
                    Text("\(Localization.get("Approve", lang: appLanguage)) (\(Int(request.timeoutSeconds))s)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.primary.opacity(0.86))
                    Spacer()
                    if queueCount > 1 {
                        Text("\(queueCount) queued")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.42))
                    }
                }

                Text(request.command)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }

                if let workingDirectory = request.workingDirectory,
                   !workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("cwd: \(workingDirectory)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.primary.opacity(0.42))
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(spacing: 8) {
                GeminiPillButton(
                    title: Localization.get("Deny", lang: appLanguage),
                    tint: Color(nsColor: .systemRed).opacity(0.85),
                    fillsAvailableWidth: true
                ) {
                    onDeny()
                }

                GeminiPillButton(
                    title: Localization.get("Once", lang: appLanguage),
                    tint: Color(nsColor: .systemBlue),
                    fillsAvailableWidth: true
                ) {
                    onApproveOnce()
                }

                GeminiPillButton(
                    title: Localization.get("Exact", lang: appLanguage),
                    tint: Color(nsColor: .systemGreen),
                    fillsAvailableWidth: true
                ) {
                    onApproveExact()
                }

                if let family = request.commandFamily {
                    GeminiPillButton(
                        title: "\(Localization.get("Always", lang: appLanguage)) \(family)",
                        tint: Color(nsColor: .systemTeal),
                        fillsAvailableWidth: true
                    ) {
                        onApproveFamily()
                    }
                }
            }
            .frame(width: 110)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    GeminiExecApprovalCard(
        request: ExecApprovalRequest(
            toolCallID: "preview-exec-approval",
            command: "swift test --filter GeminiExecApprovalTests",
            workingDirectory: "/Users/promex04/Documents/NO/notch-app",
            timeoutSeconds: 30
        ),
        queueCount: 3,
        onApproveOnce: {},
        onApproveExact: {},
        onApproveFamily: {},
        onDeny: {}
    )
    .padding(16)
    .frame(width: 520)
}
