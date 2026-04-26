import AppKit
import SwiftUI

@MainActor
final class NotchProWindowController: ObservableObject {
    static let shared = NotchProWindowController()
    
    private var window: NSWindow?
    private var hostingController: NSHostingController<NotchProRequiredView>?
    
    func show(for capability: NotchCapability, entitlementStore: NotchEntitlementStore, gemini: GeminiLiveViewModel) {
        let decision = entitlementStore.decision(for: capability)
        guard !decision.isAllowed else { return }
        
        if window == nil {
            let view = NotchProRequiredView(decision: decision, capability: capability, gemini: gemini)
            let hostingController = NSHostingController(rootView: view)
            
            let panel = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            panel.level = .floating
            panel.backgroundColor = .clear
            panel.contentViewController = hostingController
            panel.isReleasedWhenClosed = false
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            
            self.hostingController = hostingController
            self.window = panel
        } else {
            hostingController?.rootView = NotchProRequiredView(decision: decision, capability: capability, gemini: gemini)
        }
        
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    func close() {
        window?.close()
    }
}

struct NotchProRequiredView: View {
    let decision: NotchPermissionDecision
    let capability: NotchCapability
    @ObservedObject var gemini: GeminiLiveViewModel
    
    @AppStorage("app_language") private var appLanguage: String = "English"
    @AppStorage(NotchAccentColorOption.storageKey) private var accentColorID: String = NotchAccentColorOption.defaultOption.rawValue

    private var themeAccent: Color {
        NotchAccentColorOption.resolve(rawValue: accentColorID).brightColor
    }

    private var actionTitle: String {
        switch decision.recoveryAction {
        case .signIn: return Localization.get("Sign in", lang: appLanguage)
        case .refresh: return Localization.get("Refresh Pro status", lang: appLanguage)
        case .upgrade: return Localization.get("Buy Notch Pro", lang: appLanguage)
        case .none: return Localization.get("Buy Notch Pro", lang: appLanguage)
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 14) {
                // Feature badge
                HStack(spacing: 6) {
                    Circle().fill(themeAccent).frame(width: 8, height: 8)
                    Text(Localization.get(capability.displayName.capitalized, lang: appLanguage))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.88))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(themeAccent.opacity(0.16)))
                .overlay(Capsule().stroke(themeAccent.opacity(0.28), lineWidth: 1))
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text(Localization.get(decision.message, lang: appLanguage))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
                Text(actionTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer(minLength: 0)
            
            HStack(spacing: 12) {
                Spacer()
                Button {
                    NotchProWindowController.shared.close()
                } label: {
                    Text(Localization.get("Cancel", lang: appLanguage))
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                
                Button {
                    performRecoveryAction()
                    NotchProWindowController.shared.close()
                } label: {
                    HStack(spacing: 6) {
                        Text(actionTitle)
                            .font(.system(size: 12, weight: .bold))
                        Image(systemName: decision.recoveryAction == .refresh ? "arrow.clockwise" : "sparkles")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(themeAccent.opacity(0.15)))
                    .overlay(Capsule().stroke(themeAccent.opacity(0.3), lineWidth: 1))
                    .foregroundStyle(themeAccent)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
        }
        .padding(24)
        .frame(width: 360, height: 200)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.45))
        )
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func performRecoveryAction() {
        switch decision.recoveryAction {
        case .signIn:
            gemini.openWebAccountLogin()
        case .refresh:
            Task { await gemini.refreshBackendSubscriptionStatus(forceRefresh: true) }
        case .upgrade:
            gemini.openWebProCheckout()
        case .none:
            break
        }
    }
}
