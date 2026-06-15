import SwiftUI
import AppKit

@main
struct UTMGuardApp: App {
    @StateObject private var options = OptionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 860, minHeight: 600)
                .environmentObject(options)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

// MARK: - Palette
// Deliberate choice for this brief: a "spec sheet" feel — ink, a single signal
// red for errors and an amber for warnings, on warm paper. No template gradient hero.

extension Color {
    static let paper   = Color(red: 0.97, green: 0.96, blue: 0.93)
    static let ink     = Color(red: 0.11, green: 0.12, blue: 0.13)
    static let signal  = Color(red: 0.80, green: 0.22, blue: 0.18)  // error
    static let amber   = Color(red: 0.78, green: 0.55, blue: 0.10)  // warning
    static let good    = Color(red: 0.16, green: 0.45, blue: 0.34)  // valid
    static let faint   = Color(red: 0.55, green: 0.54, blue: 0.50)
}

struct RootView: View {
    enum Tab { case builder, linter, lists }
    @State private var tab: Tab = .builder

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("UTM Guard")
                    .font(.system(size: 22, weight: .heavy, design: .monospaced))
                    .foregroundColor(.ink)
                Text("build it right, or catch it before it ships")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.faint)
                Spacer()
                Picker("", selection: $tab) {
                    Text("Builder").tag(Tab.builder)
                    Text("Sheet check").tag(Tab.linter)
                    Text("Lists").tag(Tab.lists)
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color.paper)

            Divider().overlay(Color.ink.opacity(0.15))

            Group {
                switch tab {
                case .builder: BuilderView()
                case .linter:  LinterView()
                case .lists:   ManageOptionsView()
                }
            }
            .background(Color.paper)
        }
        .background(Color.paper)
    }
}
