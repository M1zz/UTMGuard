import SwiftUI
import AppKit

/// Paste the existing sheet (tab-separated) and get every problem row flagged.
/// This is the "catch it before it ships" half — it audits work already done.
struct LinterView: View {
    @EnvironmentObject var options: OptionStore
    @State private var raw: String = ""
    @State private var links: [UTMLink] = []
    @State private var issuesByRow: [UUID: [Issue]] = [:]
    @State private var onlyProblems = true
    @State private var importMsg: String?

    private var totalErrors: Int {
        issuesByRow.values.flatMap { $0 }.filter { $0.level == .error }.count
    }
    private var totalWarnings: Int {
        issuesByRow.values.flatMap { $0 }.filter { $0.level == .warning }.count
    }
    private var problemRows: [UTMLink] {
        links.filter { !(issuesByRow[$0.id]?.isEmpty ?? true) }
    }
    private var shownRows: [UTMLink] { onlyProblems ? problemRows : links }

    var body: some View {
        HSplitView {
            // Left: paste area
            VStack(alignment: .leading, spacing: 12) {
                Text("PASTE YOUR SHEET")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.faint).tracking(1.5)
                Text("Copy the rows from your spreadsheet (with the header row) and paste below.")
                    .font(.system(size: 11, design: .monospaced)).foregroundColor(.faint)

                TextEditor(text: $raw)
                    .font(.system(size: 11, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color.white.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.ink.opacity(0.15), lineWidth: 1))

                HStack(spacing: 10) {
                    Button {
                        links = SheetParser.parse(raw)
                        issuesByRow = Validator.validateSet(links)
                        importMsg = nil
                    } label: {
                        Label("Check \(links.isEmpty ? "" : "again")", systemImage: "magnifyingglass")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    }
                    if !links.isEmpty {
                        Button {
                            let added = options.importFrom(links)
                            importMsg = "\(added)개 새 선택지 등록됨"
                        } label: {
                            Label("선택지로 등록", systemImage: "square.and.arrow.down")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        }
                    }
                }
                if let importMsg {
                    Text(importMsg).font(.system(size: 11, design: .monospaced)).foregroundColor(.good)
                }
            }
            .padding(20)
            .frame(minWidth: 320)

            // Right: results
            VStack(alignment: .leading, spacing: 0) {
                if links.isEmpty {
                    emptyState
                } else {
                    summaryBar
                    Divider().overlay(Color.ink.opacity(0.1))
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(shownRows) { link in
                                rowCard(link)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .frame(minWidth: 420)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tablecells.badge.ellipsis")
                .font(.system(size: 40)).foregroundColor(.faint)
            Text("No rows yet")
                .font(.system(size: 15, weight: .semibold, design: .monospaced)).foregroundColor(.ink)
            Text("Paste your sheet on the left and press Check.")
                .font(.system(size: 12, design: .monospaced)).foregroundColor(.faint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var summaryBar: some View {
        HStack(spacing: 16) {
            stat("\(links.count)", "rows", .ink)
            stat("\(totalErrors)", "errors", .signal)
            stat("\(totalWarnings)", "warnings", .amber)
            stat("\(links.count - problemRows.count)", "clean", .good)
            Spacer()
            Toggle("Problems only", isOn: $onlyProblems)
                .toggleStyle(.checkbox)
                .font(.system(size: 12, design: .monospaced))
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private func stat(_ n: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(n).font(.system(size: 20, weight: .heavy, design: .monospaced)).foregroundColor(color)
            Text(label).font(.system(size: 10, design: .monospaced)).foregroundColor(.faint)
        }
    }

    private func rowCard(_ link: UTMLink) -> some View {
        let issues = issuesByRow[link.id] ?? []
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(link.campaignName.isEmpty ? "(no label)" : link.campaignName)
                    .font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.ink)
                if !link.channel.isEmpty {
                    Text(link.channel)
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(.faint)
                }
                Spacer()
                if issues.isEmpty {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.good)
                }
            }
            Text("\(link.source.isEmpty ? "∅" : link.source) / \(link.medium.isEmpty ? "∅" : link.medium) / \(link.campaign.isEmpty ? "∅" : link.campaign) / \(link.content.isEmpty ? "∅" : link.content)")
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.faint)
            ForEach(issues) { issue in
                IssueRow(issue: issue)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.5))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.ink.opacity(0.12), lineWidth: 1))
    }
}
