import Foundation

// MARK: - Core model

/// One tracked link. Either built fresh in the Builder, or parsed from a pasted sheet row.
struct UTMLink: Identifiable, Equatable {
    var id = UUID()
    var campaignName: String = ""   // human label (캠페인명_국문)
    var channel: String = ""        // 채널/매체
    var baseURL: String = ""        // Landing Page Base URL
    var source: String = ""         // utm_source
    var medium: String = ""         // utm_medium
    var campaign: String = ""       // utm_campaign
    var content: String = ""        // utm_content

    /// The full URL with parameters appended. Single source of truth so the
    /// "Whole URL" can never drift away from its components.
    var fullURL: String {
        guard !baseURL.isEmpty else { return "" }
        var params: [String] = []
        func add(_ key: String, _ value: String) {
            if !value.isEmpty { params.append("\(key)=\(value)") }
        }
        add("utm_source", source)
        add("utm_medium", medium)
        add("utm_campaign", campaign)
        add("utm_content", content)
        guard !params.isEmpty else { return baseURL }
        let sep = baseURL.contains("?") ? "&" : "?"
        return baseURL + sep + params.joined(separator: "&")
    }
}

// MARK: - Issue reporting

enum IssueLevel: String {
    case error   // breaks tracking / unusable
    case warning // works but will fragment or confuse reports

    var label: String {
        switch self {
        case .error:   return "Error"
        case .warning: return "Warning"
        }
    }
}

struct Issue: Identifiable {
    let id = UUID()
    let level: IssueLevel
    let field: String      // which column the problem lives in
    let message: String    // what is wrong, in plain terms
    let fix: String?       // suggested corrected value, if there is one
}

// MARK: - Canonical vocabulary
//
// Drawn from the recurring values in the real sheet so the linter can flag
// the casing drift and typos that silently split a campaign in GA.

enum Vocab {
    /// Known-good source values. Lowercase is the rule everywhere.
    static let sources: Set<String> = [
        "newsletter", "ig", "kakao", "naver", "edm", "linkedin", "yt",
        "keynote", "leaflet", "xbanner", "seminar", "chat", "figma",
        "uni-letter", "web-event", "poster", "merch", "discord", "everytime",
        "linkareer", "careerly", "thread", "stibee", "zoomchat", "web",
        "community", "ad", "postit", "uni-site", "sopt", "maintenance",
        "apple-homepage", "subscribers", "learner"
    ]
}

// MARK: - Parsing a pasted sheet

enum SheetParser {
    /// Columns expected in the marketing sheet, by header keyword.
    /// We locate them by header text so column order can shift.
    static func parse(_ raw: String) -> [UTMLink] {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let headerLine = lines.first else { return [] }
        // Numbers "copy cells" pastes tab-separated; "Export → CSV" gives commas.
        let sep = headerLine.contains("\t") ? "\t" : ","
        let headers = headerLine.components(separatedBy: sep)

        func index(containing needle: String) -> Int? {
            headers.firstIndex { $0.lowercased().contains(needle.lowercased()) }
        }

        let iName     = index(containing: "캠페인명") ?? 0
        let iChannel  = index(containing: "채널") ?? 1
        let iBase     = index(containing: "Landing Page Base") ?? index(containing: "Base URL")
        let iSource   = index(containing: "UTM_source") ?? index(containing: "source")
        let iMedium   = index(containing: "UTM_medium") ?? index(containing: "medium")
        let iCampaign = index(containing: "UTM_campaign") ?? index(containing: "campaign")
        let iContent  = index(containing: "축약이름") ?? index(containing: "content")

        func cell(_ cols: [String], _ idx: Int?) -> String {
            guard let idx, idx >= 0, idx < cols.count else { return "" }
            return cols[idx].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var result: [UTMLink] = []
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let cols = line.components(separatedBy: sep)
            let link = UTMLink(
                campaignName: cell(cols, iName),
                channel:      cell(cols, iChannel),
                baseURL:      cell(cols, iBase),
                source:       cell(cols, iSource),
                medium:       cell(cols, iMedium),
                campaign:     cell(cols, iCampaign),
                content:      cell(cols, iContent)
            )
            // Skip fully empty rows (the sheet has several spacer rows).
            if link.source.isEmpty && link.medium.isEmpty && link.campaign.isEmpty
                && link.baseURL.isEmpty && link.campaignName.isEmpty { continue }
            result.append(link)
        }
        return result
    }
}
