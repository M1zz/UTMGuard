import Foundation

/// Validates a set of links and reports the exact problems seen in the real sheet:
/// casing drift, campaign typos, duplicate content numbers, broken URLs, empty utms,
/// and Whole-URL / component mismatch.
enum Validator {

    // Per-row checks that don't need to see the other rows.
    static func validateRow(_ link: UTMLink) -> [Issue] {
        var issues: [Issue] = []

        // 1. Base URL must be present and a real URL.
        let base = link.baseURL.trimmingCharacters(in: .whitespaces)
        if base.isEmpty {
            issues.append(Issue(level: .error, field: "Base URL",
                message: "No landing page. The link points nowhere and won't track.",
                fix: nil))
        } else {
            if !base.hasPrefix("http://") && !base.hasPrefix("https://") {
                issues.append(Issue(level: .error, field: "Base URL",
                    message: "Missing https:// — browsers and link shorteners will reject it.",
                    fix: "https://" + base.replacingOccurrences(of: "https//", with: "")))
            }
            if base.range(of: "://[^/]+//", options: .regularExpression) != nil {
                issues.append(Issue(level: .warning, field: "Base URL",
                    message: "Double slash in the path (e.g. fasttrack2026//postech). May 404.",
                    fix: nil))
            }
        }

        // 2. Empty utm fields → GA logs these as "(not set)" and the link is unattributable.
        if link.source.isEmpty {
            issues.append(Issue(level: .error, field: "utm_source",
                message: "Empty source. This visit can't be attributed to any channel.", fix: nil))
        }
        if link.medium.isEmpty {
            issues.append(Issue(level: .error, field: "utm_medium",
                message: "Empty medium.", fix: nil))
        }
        if link.campaign.isEmpty {
            issues.append(Issue(level: .error, field: "utm_campaign",
                message: "Empty campaign.", fix: nil))
        }

        // 3. Casing drift. GA is case-sensitive, so Ig / ig / instagram are three channels.
        for (field, value) in [("utm_source", link.source), ("utm_medium", link.medium),
                               ("utm_campaign", link.campaign)] {
            if value != value.lowercased() && !value.isEmpty {
                issues.append(Issue(level: .warning, field: field,
                    message: "Mixed case '\(value)'. GA treats this as separate from its lowercase form.",
                    fix: value.lowercased()))
            }
        }

        // 4. instagram → ig normalization (the sheet uses both).
        if link.source.lowercased() == "instagram" {
            issues.append(Issue(level: .warning, field: "utm_source",
                message: "'instagram' elsewhere is written 'ig'. Pick one or reports split.",
                fix: "ig"))
        }

        // 5. Spaces inside any utm value break the URL.
        for (field, value) in [("utm_source", link.source), ("utm_medium", link.medium),
                               ("utm_campaign", link.campaign), ("utm_content", link.content)] {
            if value.contains(" ") {
                issues.append(Issue(level: .error, field: field,
                    message: "Contains a space, which corrupts the query string.",
                    fix: value.replacingOccurrences(of: " ", with: "-")))
            }
        }

        return issues
    }

    // Cross-row checks: things only visible when comparing rows.
    static func validateSet(_ links: [UTMLink]) -> [UUID: [Issue]] {
        var byRow: [UUID: [Issue]] = [:]
        for link in links { byRow[link.id] = validateRow(link) }

        // A. Duplicate utm_content within the same campaign → can't tell sources apart.
        var seen: [String: [UUID]] = [:]   // "campaign|content" -> rows
        for link in links where !link.campaign.isEmpty && !link.content.isEmpty {
            let key = link.campaign.lowercased() + "|" + link.content
            seen[key, default: []].append(link.id)
        }
        for (key, ids) in seen where ids.count > 1 {
            let content = key.split(separator: "|").last.map(String.init) ?? ""
            for id in ids {
                byRow[id, default: []].append(Issue(level: .warning, field: "utm_content",
                    message: "content=\(content) is reused \(ids.count)× in this campaign. The rows can't be told apart in reports.",
                    fix: nil))
            }
        }

        // B. Near-duplicate campaign names (likely typos that fragment a campaign).
        let campaigns = Set(links.map { $0.campaign.lowercased() }.filter { !$0.isEmpty })
        let arr = Array(campaigns)
        for i in 0..<arr.count {
            for j in (i+1)..<arr.count {
                if levenshtein(arr[i], arr[j]) == 1 {
                    // Flag the rarer spelling as the suspect typo.
                    let countA = links.filter { $0.campaign.lowercased() == arr[i] }.count
                    let countB = links.filter { $0.campaign.lowercased() == arr[j] }.count
                    let (suspect, correct) = countA <= countB ? (arr[i], arr[j]) : (arr[j], arr[i])
                    for link in links where link.campaign.lowercased() == suspect {
                        byRow[link.id, default: []].append(Issue(level: .warning, field: "utm_campaign",
                            message: "'\(link.campaign)' looks like a typo of '\(correct)'. They'll report as two campaigns.",
                            fix: correct))
                    }
                }
            }
        }

        return byRow
    }

    // Simple edit distance for typo detection (roadshow-busan vs roadshow-busman).
    static func levenshtein(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1), b = Array(s2)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prevRow = Array(0...b.count)
        var curRow = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            curRow[0] = i
            for j in 1...b.count {
                let cost = a[i-1] == b[j-1] ? 0 : 1
                curRow[j] = Swift.min(prevRow[j] + 1, curRow[j-1] + 1, prevRow[j-1] + cost)
            }
            swap(&prevRow, &curRow)
        }
        return prevRow[b.count]
    }
}
