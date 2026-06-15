import SwiftUI
import AppKit

/// Builds a clean tracked link. The user picks source/medium from known values
/// so the casing/typo problems can't happen at the source. The full URL is
/// generated, never typed — so Whole URL and components can never disagree.
struct BuilderView: View {
    @EnvironmentObject var options: OptionStore
    @State private var link = UTMLink(baseURL: "https://developeracademy.postech.ac.kr/")
    @State private var copied = false

    private var liveIssues: [Issue] { Validator.validateRow(link) + contentCollision }

    /// Prevention, not detection: a content already used in this campaign is an
    /// error here, with the next free number offered as the one-tap fix.
    private var contentCollision: [Issue] {
        guard !link.campaign.isEmpty, !link.content.isEmpty,
              options.isContentTaken(link.content, in: link.campaign) else { return [] }
        return [Issue(level: .error, field: "utm_content",
                      message: "이 campaign에서 이미 쓰인 content입니다. 중복되면 리포트에서 행을 구분할 수 없습니다.",
                      fix: options.nextContent(for: link.campaign))]
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: form
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field("Campaign label", text: $link.campaignName,
                          hint: "Internal name. e.g. 패스트 트랙 봄시즌")
                    field("Landing page URL", text: $link.baseURL,
                          hint: "Where the click lands. Must start with https://", mono: true)

                    Divider().overlay(Color.ink.opacity(0.1))

                    ManagedPickField(field: .source, value: $link.source,
                                     options: options.sources,
                                     hint: "Where it's posted: ig, kakao, newsletter…",
                                     display: options.displayLabel,
                                     onAdd: { v, m in options.add(v, meaning: m, to: .source) })
                    ManagedPickField(field: .medium, value: $link.medium,
                                     options: options.mediums,
                                     hint: "Format: story, post, edm, qr…",
                                     display: options.displayLabel,
                                     onAdd: { v, m in options.add(v, meaning: m, to: .medium) })
                    ManagedPickField(field: .campaign, value: $link.campaign,
                                     options: options.campaigns,
                                     hint: "Campaign slug, reused across all its links",
                                     display: options.displayLabel,
                                     onAdd: { v, m in options.add(v, meaning: m, to: .campaign) })
                    contentField
                }
                .padding(24)
                .onChange(of: link.campaign) { _, c in
                    // New campaign and content still blank → suggest the next free number.
                    if !c.isEmpty && link.content.isEmpty { link.content = options.nextContent(for: c) }
                }
            }
            .frame(width: 380)

            Divider().overlay(Color.ink.opacity(0.15))

            // Right: live output + checks
            VStack(alignment: .leading, spacing: 16) {
                Text("GENERATED LINK")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.faint)
                    .tracking(1.5)

                Text(link.fullURL.isEmpty ? "—" : link.fullURL)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.ink)
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.ink.opacity(0.15), lineWidth: 1))

                HStack {
                    Button(action: copy) {
                        Label(copied ? "Copied" : "Copy link",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    }
                    .disabled(link.fullURL.isEmpty || liveIssues.contains { $0.level == .error })
                    Spacer()
                    statusBadge
                }

                Divider().overlay(Color.ink.opacity(0.1))

                if liveIssues.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill").foregroundColor(.good)
                        Text("Clean. Safe to ship.")
                            .font(.system(size: 13, design: .monospaced)).foregroundColor(.good)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(liveIssues) { issue in
                            IssueRow(issue: issue) { fix in apply(fix, for: issue.field) }
                        }
                    }
                }
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var statusBadge: some View {
        let hasError = liveIssues.contains { $0.level == .error }
        let hasWarn  = liveIssues.contains { $0.level == .warning }
        let (text, color): (String, Color) =
            hasError ? ("blocked", .signal) : hasWarn ? ("check warnings", .amber) : ("ready", .good)
        return Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link.fullURL, forType: .string)
        // Mark this content used so the next link auto-numbers past it (and syncs).
        options.registerContent(link.content, in: link.campaign)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
    }

    // utm_content with one-tap auto-numbering against the campaign's used values.
    @ViewBuilder
    private var contentField: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("utm_content")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.ink)
                Spacer()
                Button {
                    link.content = options.nextContent(for: link.campaign)
                } label: {
                    Label("자동 번호", systemImage: "number")
                        .font(.system(size: 10, design: .monospaced))
                }
                .buttonStyle(.plain)
                .foregroundColor(link.campaign.isEmpty ? .faint : .good)
                .disabled(link.campaign.isEmpty)
            }
            TextField("", text: $link.content)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .padding(8)
                .background(Color.white.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.ink.opacity(0.15), lineWidth: 1))
            Text(link.campaign.isEmpty
                 ? "campaign을 먼저 고르면 다음 빈 번호가 자동으로 채워집니다."
                 : "campaign 안에서 고유. '자동 번호'가 다음 빈 번호를 채웁니다.")
                .font(.system(size: 10, design: .monospaced)).foregroundColor(.faint)
        }
    }

    private func apply(_ fix: String, for field: String) {
        switch field {
        case "utm_source":   link.source = fix
        case "utm_medium":   link.medium = fix
        case "utm_campaign": link.campaign = fix
        case "utm_content":  link.content = fix
        case "Base URL":     link.baseURL = fix
        default: break
        }
    }

    // MARK: field builders

    @ViewBuilder
    private func field(_ label: String, text: Binding<String>, hint: String,
                       mono: Bool = false, lowercaseOnly: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.ink)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: mono ? .monospaced : .default))
                .padding(8)
                .background(Color.white.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.ink.opacity(0.15), lineWidth: 1))
                .onChange(of: text.wrappedValue) { _, newValue in
                    if lowercaseOnly { text.wrappedValue = newValue.lowercased() }
                }
            Text(hint).font(.system(size: 10, design: .monospaced)).foregroundColor(.faint)
        }
    }

}

// MARK: - Issue row, shared

struct IssueRow: View {
    let issue: Issue
    var onApplyFix: ((String) -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: issue.level == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(issue.level == .error ? .signal : .amber)
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: 3) {
                Text(issue.field)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.faint)
                Text(issue.message)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let fix = issue.fix, let onApplyFix {
                    Button {
                        onApplyFix(fix)
                    } label: {
                        Text("fix → \(fix)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.good)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(10)
        .background((issue.level == .error ? Color.signal : Color.amber).opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 5)
            .stroke((issue.level == .error ? Color.signal : Color.amber).opacity(0.3), lineWidth: 1))
    }
}
