import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Store
//
// User-managed, persisted choice lists for the Builder dropdowns. Seeded from the
// canonical vocabulary, then grown by the user — typing a value once saves it for
// reuse, so the casing/typo drift the linter catches can't reappear at input time.
// You can also import the values already in your working Numbers/CSV sheet.

final class OptionStore: ObservableObject {
    enum Field: String, CaseIterable, Identifiable {
        case source   = "utm_source"
        case medium   = "utm_medium"
        case campaign = "utm_campaign"
        var id: String { rawValue }
    }

    @Published var sources: [String]   { didSet { save(); pushIfNeeded() } }
    @Published var mediums: [String]   { didSet { save(); pushIfNeeded() } }
    @Published var campaigns: [String] { didSet { save(); pushIfNeeded() } }

    /// Human meaning for a value, e.g. "ig" → "인스타그램". Display only; the
    /// value written into the link is always the short code.
    @Published var meanings: [String: String] { didSet { save(); pushIfNeeded() } }

    /// utm_content values already used, keyed by normalized campaign. Powers the
    /// auto-numbering that makes content collisions impossible, not just flagged.
    @Published var usedContent: [String: [String]] { didSet { save(); pushIfNeeded() } }

    private let kSources     = "utmguard.options.sources"
    private let kMediums     = "utmguard.options.mediums"
    private let kCampaigns   = "utmguard.options.campaigns"
    private let kMeanings    = "utmguard.options.meanings"
    private let kUsedContent = "utmguard.options.usedContent"

    // MARK: Real-time sync state
    @Published private(set) var syncFileName: String? = nil
    @Published private(set) var syncStatus: String = "꺼짐"
    private var syncURL: URL?
    private var syncTimer: Timer?
    private var syncMTime: Date?
    private var applyingRemote = false
    private let kSyncBookmark = "utmguard.sync.bookmark"
    private var syncActive: Bool { syncURL != nil }

    /// Sensible starting mediums (overridden once the user imports their sheet).
    static let seedMediums = ["story", "post", "feed", "reels", "edm", "email",
                              "qr", "dm", "banner", "bio-link"]

    /// Default Korean meanings for the canonical vocabulary. The user can edit any.
    static let seedMeanings: [String: String] = [
        "newsletter": "뉴스레터", "ig": "인스타그램", "kakao": "카카오톡", "naver": "네이버",
        "edm": "이메일 DM", "linkedin": "링크드인", "yt": "유튜브", "keynote": "키노트",
        "leaflet": "전단지", "xbanner": "엑스배너", "seminar": "세미나", "chat": "채팅",
        "figma": "피그마", "uni-letter": "대학 레터", "web-event": "웹 이벤트", "poster": "포스터",
        "merch": "굿즈", "discord": "디스코드", "everytime": "에브리타임", "linkareer": "링커리어",
        "careerly": "커리어리", "thread": "스레드", "stibee": "스티비", "zoomchat": "줌 채팅",
        "web": "웹", "community": "커뮤니티", "ad": "광고", "postit": "포스트잇",
        "uni-site": "대학 사이트", "sopt": "SOPT", "maintenance": "유지보수",
        "apple-homepage": "애플 홈페이지", "subscribers": "구독자", "learner": "러너",
        // mediums
        "story": "스토리", "post": "피드 포스트", "feed": "피드", "reels": "릴스",
        "email": "이메일", "qr": "QR 코드", "dm": "다이렉트 메시지", "banner": "배너",
        "bio-link": "프로필 링크",
    ]

    init() {
        let d = UserDefaults.standard
        sources   = d.stringArray(forKey: kSources)   ?? Array(Vocab.sources).sorted()
        mediums   = d.stringArray(forKey: kMediums)   ?? OptionStore.seedMediums
        campaigns = d.stringArray(forKey: kCampaigns) ?? []
        meanings = OptionStore.decodeDict(d.data(forKey: kMeanings)) ?? OptionStore.seedMeanings
        usedContent = OptionStore.decodeDict(d.data(forKey: kUsedContent)) ?? [:]
        resumeSyncIfLinked()
    }

    private static func decodeDict<V: Decodable>(_ data: Data?) -> [String: V]? {
        guard let data else { return nil }
        return try? JSONDecoder().decode([String: V].self, from: data)
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(sources,   forKey: kSources)
        d.set(mediums,   forKey: kMediums)
        d.set(campaigns, forKey: kCampaigns)
        d.set(try? JSONEncoder().encode(meanings),    forKey: kMeanings)
        d.set(try? JSONEncoder().encode(usedContent), forKey: kUsedContent)
    }

    /// lowercase, trimmed, spaces → hyphens — the option list itself stays clean.
    static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
         .lowercased()
         .replacingOccurrences(of: " ", with: "-")
    }

    func list(_ field: Field) -> [String] {
        switch field {
        case .source:   return sources
        case .medium:   return mediums
        case .campaign: return campaigns
        }
    }

    func add(_ raw: String, to field: Field) { add(raw, meaning: "", to: field) }

    func add(_ raw: String, meaning: String, to field: Field) {
        let v = OptionStore.normalize(raw)
        guard !v.isEmpty else { return }
        switch field {
        case .source:   if !sources.contains(v)   { sources   = (sources   + [v]).sorted() }
        case .medium:   if !mediums.contains(v)   { mediums   = (mediums   + [v]).sorted() }
        case .campaign: if !campaigns.contains(v) { campaigns = (campaigns + [v]).sorted() }
        }
        let m = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        if !m.isEmpty { meanings[v] = m }
    }

    func remove(_ value: String, from field: Field) {
        switch field {
        case .source:   sources.removeAll   { $0 == value }
        case .medium:   mediums.removeAll   { $0 == value }
        case .campaign: campaigns.removeAll { $0 == value }
        }
    }

    // MARK: Meanings (display label "의미 (value)")

    func meaning(_ value: String) -> String? {
        let m = meanings[OptionStore.normalize(value)]
        return (m?.isEmpty ?? true) ? nil : m
    }

    func setMeaning(_ meaning: String, for value: String) {
        let v = OptionStore.normalize(value)
        let m = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        if m.isEmpty { meanings.removeValue(forKey: v) } else { meanings[v] = m }
    }

    /// "인스타그램 (ig)" when a meaning exists, otherwise just the value.
    func displayLabel(_ value: String) -> String {
        guard !value.isEmpty else { return "" }
        if let m = meaning(value) { return "\(m) (\(value))" }
        return value
    }

    // MARK: utm_content auto-numbering — collision becomes impossible

    /// Smallest zero-padded number not yet used in this campaign (01, 02, …).
    func nextContent(for campaign: String) -> String {
        let used = Set(usedContent[OptionStore.normalize(campaign)] ?? [])
        var n = 1
        while used.contains(String(format: "%02d", n)) { n += 1 }
        return String(format: "%02d", n)
    }

    func isContentTaken(_ content: String, in campaign: String) -> Bool {
        let c = content.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty else { return false }
        return (usedContent[OptionStore.normalize(campaign)] ?? []).contains(c)
    }

    func registerContent(_ content: String, in campaign: String) {
        let key = OptionStore.normalize(campaign)
        let c = content.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !c.isEmpty else { return }
        var arr = usedContent[key] ?? []
        if !arr.contains(c) { arr.append(c); usedContent[key] = arr.sorted() }
    }

    /// Bootstrap the lists from an already-parsed sheet: the distinct values
    /// actually in use become the dropdown choices. Returns how many were new.
    @discardableResult
    func importFrom(_ links: [UTMLink]) -> Int {
        var s = Set(sources), m = Set(mediums), c = Set(campaigns)
        for link in links {
            let sv = OptionStore.normalize(link.source);   if !sv.isEmpty { s.insert(sv) }
            let mv = OptionStore.normalize(link.medium);   if !mv.isEmpty { m.insert(mv) }
            let cv = OptionStore.normalize(link.campaign); if !cv.isEmpty { c.insert(cv) }
        }
        let added = (s.count - sources.count) + (m.count - mediums.count) + (c.count - campaigns.count)
        sources = s.sorted(); mediums = m.sorted(); campaigns = c.sorted()

        // Record the content already used per campaign, so auto-numbering avoids it.
        var uc = usedContent
        for link in links {
            let ck = OptionStore.normalize(link.campaign)
            let cv = link.content.trimmingCharacters(in: .whitespaces)
            guard !ck.isEmpty, !cv.isEmpty else { continue }
            var set = Set(uc[ck] ?? []); set.insert(cv); uc[ck] = set.sorted()
        }
        usedContent = uc
        return added
    }

    var total: Int { sources.count + mediums.count + campaigns.count }

    // MARK: Team sharing — one canonical file the team imports

    func snapshot() -> OptionsSnapshot {
        OptionsSnapshot(sources: sources, mediums: mediums, campaigns: campaigns,
                        meanings: meanings, usedContent: usedContent)
    }

    func encoded() -> Data? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(snapshot())
    }

    /// Merge a shared snapshot into the local lists. Returns how many list values were new.
    @discardableResult
    func merge(_ snap: OptionsSnapshot) -> Int {
        var s = Set(sources), m = Set(mediums), c = Set(campaigns)
        for v in snap.sources   { let n = OptionStore.normalize(v); if !n.isEmpty { s.insert(n) } }
        for v in snap.mediums   { let n = OptionStore.normalize(v); if !n.isEmpty { m.insert(n) } }
        for v in snap.campaigns { let n = OptionStore.normalize(v); if !n.isEmpty { c.insert(n) } }
        let added = (s.count - sources.count) + (m.count - mediums.count) + (c.count - campaigns.count)
        sources = s.sorted(); mediums = m.sorted(); campaigns = c.sorted()

        // Meanings: adopt any the remote has that we lack (keep our own otherwise).
        var mn = meanings
        for (k, v) in snap.meanings where (mn[k]?.isEmpty ?? true) && !v.isEmpty { mn[k] = v }
        if mn != meanings { meanings = mn }

        // Used content: union per campaign.
        var uc = usedContent
        for (k, vals) in snap.usedContent {
            var set = Set(uc[k] ?? []); vals.forEach { set.insert($0) }; uc[k] = set.sorted()
        }
        if uc != usedContent { usedContent = uc }

        return added
    }

    // MARK: - Real-time sync
    //
    // The shared file is a union of every client's lists. Because merging only
    // ever ADDS (set union), sync is monotonic — no conflicts, no ordering
    // problems, always convergent. We poll the file's modification date (robust
    // against the atomic file replacement Dropbox/Drive/iCloud do) and write our
    // own changes back; recording our write's mtime stops the feedback loop.

    /// Link a shared .json file: pull what's there, push our extras, then watch it.
    func linkSyncFile(_ url: URL) {
        if let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: kSyncBookmark)
        }
        beginSync(url)
    }

    func unlinkSync() {
        syncTimer?.invalidate(); syncTimer = nil
        syncURL = nil; syncMTime = nil
        syncFileName = nil; syncStatus = "꺼짐"
        UserDefaults.standard.removeObject(forKey: kSyncBookmark)
    }

    private func resumeSyncIfLinked() {
        guard let data = UserDefaults.standard.data(forKey: kSyncBookmark) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else {
            UserDefaults.standard.removeObject(forKey: kSyncBookmark); return
        }
        beginSync(url)
    }

    private func beginSync(_ url: URL) {
        syncURL = url
        syncFileName = url.lastPathComponent
        if FileManager.default.fileExists(atPath: url.path) {
            pullRemote()           // adopt the shared list, push back if we have extras
        } else {
            pushLocal()            // first writer creates the file
        }
        scheduleTimer()
    }

    private func scheduleTimer() {
        syncTimer?.invalidate()
        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        syncTimer = t
    }

    private func tick() {
        guard let url = syncURL, let m = fileMTime(url), m != syncMTime else { return }
        pullRemote()
    }

    private func fileMTime(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private func pullRemote() {
        guard let url = syncURL else { return }
        guard let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(OptionsSnapshot.self, from: data) else {
            syncStatus = "원격 읽기 실패"; return
        }
        applyingRemote = true
        let added = merge(snap)        // union remote into local (suppresses push)
        applyingRemote = false

        // Did we hold anything the file lacks? If so, write the union back.
        if hasExtraBeyond(snap) {
            pushLocal()                // converges; other clients then match and stop
        } else {
            syncMTime = fileMTime(url) // in sync — just remember the timestamp
            syncStatus = added > 0 ? "동기화됨 (+\(added))" : "동기화됨"
        }
    }

    /// True if our local state contains any value/meaning/content the snapshot lacks.
    private func hasExtraBeyond(_ snap: OptionsSnapshot) -> Bool {
        if !Set(sources).subtracting(snap.sources.map(OptionStore.normalize)).isEmpty { return true }
        if !Set(mediums).subtracting(snap.mediums.map(OptionStore.normalize)).isEmpty { return true }
        if !Set(campaigns).subtracting(snap.campaigns.map(OptionStore.normalize)).isEmpty { return true }
        for (k, v) in meanings where !v.isEmpty && (snap.meanings[k]?.isEmpty ?? true) { return true }
        for (k, vals) in usedContent {
            if !Set(vals).subtracting(snap.usedContent[k] ?? []).isEmpty { return true }
        }
        return false
    }

    private func pushIfNeeded() {
        guard syncActive, !applyingRemote else { return }
        pushLocal()
    }

    private func pushLocal() {
        guard let url = syncURL, let data = encoded() else { return }
        do {
            try data.write(to: url, options: .atomic)
            syncMTime = fileMTime(url)  // record our own write so tick() ignores it
            syncStatus = "동기화됨"
        } catch {
            syncStatus = "쓰기 실패"
        }
    }
}

/// The shareable file format: the lists, their meanings, and used content numbers.
struct OptionsSnapshot: Codable {
    var sources: [String] = []
    var mediums: [String] = []
    var campaigns: [String] = []
    var meanings: [String: String] = [:]
    var usedContent: [String: [String]] = [:]
}

// MARK: - Reusable dropdown field

/// A field whose value is chosen from the saved list. New values are added through
/// "새 값 추가…", normalized, and persisted — so the same option exists next time.
struct ManagedPickField: View {
    let field: OptionStore.Field
    @Binding var value: String
    let options: [String]
    let hint: String
    var display: (String) -> String = { $0 }   // "인스타그램 (ig)"
    var onAdd: (String, String) -> Void        // (value, meaning)

    @State private var adding = false
    @State private var draft = ""
    @State private var draftMeaning = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(field.rawValue)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.ink)

            Menu {
                ForEach(options, id: \.self) { opt in
                    Button(display(opt)) { value = opt }
                }
                if !options.isEmpty { Divider() }
                Button { draft = ""; draftMeaning = ""; adding = true } label: {
                    Label("새 값 추가…", systemImage: "plus")
                }
            } label: {
                HStack {
                    Text(value.isEmpty ? "선택…" : display(value))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(value.isEmpty ? .faint : .ink)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9)).foregroundColor(.faint)
                }
                .padding(8)
                .background(Color.white.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.ink.opacity(0.15), lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

            Text(hint).font(.system(size: 10, design: .monospaced)).foregroundColor(.faint)
        }
        .alert("새 \(field.rawValue) 값", isPresented: $adding) {
            TextField("값 (소문자, 공백 없이) 예: ig", text: $draft)
            TextField("의미 (선택) 예: 인스타그램", text: $draftMeaning)
            Button("추가") { commit() }
            Button("취소", role: .cancel) { draft = ""; draftMeaning = "" }
        } message: {
            Text("값은 링크에 들어가고, 의미는 드롭다운에 '의미 (값)'으로 표시됩니다.")
        }
    }

    private func commit() {
        let v = OptionStore.normalize(draft)
        guard !v.isEmpty else { return }
        onAdd(v, draftMeaning)
        value = v
        draft = ""; draftMeaning = ""
    }
}

// MARK: - Lists management + import

struct ManageOptionsView: View {
    @EnvironmentObject var store: OptionStore
    @State private var raw = ""
    @State private var importMsg: String?
    @State private var picking = false

    var body: some View {
        HSplitView {
            importPanel
            listsPanel
        }
    }

    private var importPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("시트에서 선택지 가져오기")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.faint).tracking(1.5)
            Text("Numbers에서 표를 복사해 아래에 붙여넣거나, CSV로 내보낸 파일을 여세요 (헤더 행 포함). 실제 쓰인 source / medium / campaign 값이 드롭다운 선택지로 등록됩니다.")
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.faint)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $raw)
                .font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color.white.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.ink.opacity(0.15), lineWidth: 1))

            HStack(spacing: 10) {
                Button { runImport(SheetParser.parse(raw)) } label: {
                    Label("붙여넣은 표 가져오기", systemImage: "square.and.arrow.down")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                }
                Button { picking = true } label: {
                    Label("CSV 파일 열기…", systemImage: "folder")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                }
            }
            if let importMsg {
                Text(importMsg).font(.system(size: 11, design: .monospaced)).foregroundColor(.good)
            }

            Divider().overlay(Color.ink.opacity(0.1)).padding(.vertical, 4)

            Text("팀 공유")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.faint).tracking(1.5)
            Text("선택지를 .json으로 내보내 공유 드라이브/리포지토리에 두면, 팀원이 가져와 같은 표준 목록을 씁니다.")
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.faint)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button(action: exportLists) {
                    Label("선택지 내보내기", systemImage: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                }
                Button(action: importShared) {
                    Label("공유 목록 가져오기", systemImage: "person.2")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                }
            }

            Divider().overlay(Color.ink.opacity(0.1)).padding(.vertical, 4)

            Text("실시간 동기화")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.faint).tracking(1.5)
            Text("공유 .json 파일에 연결하면 변경이 자동 반영됩니다(2초 간격, 양방향). Dropbox·Drive·Git 폴더의 파일을 쓰면 팀 전체가 동기화됩니다.")
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.faint)
                .fixedSize(horizontal: false, vertical: true)

            if let name = store.syncFileName {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12)).foregroundColor(.good)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundColor(.ink)
                        Text(store.syncStatus).font(.system(size: 10, design: .monospaced)).foregroundColor(.faint)
                    }
                    Spacer()
                    Button("연결 해제") { store.unlinkSync() }
                        .font(.system(size: 12, design: .monospaced))
                }
                .padding(10)
                .background(Color.good.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.good.opacity(0.3), lineWidth: 1))
            } else {
                Button(action: linkSync) {
                    Label("공유 파일에 연결…", systemImage: "link")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 320)
        .fileImporter(isPresented: $picking,
                      allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                importMsg = "파일을 읽지 못했습니다."
                return
            }
            raw = content
            runImport(SheetParser.parse(content))
        }
    }

    private func runImport(_ links: [UTMLink]) {
        let added = store.importFrom(links)
        importMsg = "\(links.count)개 행에서 \(added)개 새 선택지 추가됨"
    }

    private func exportLists() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "utm-guard-lists.json"
        guard panel.runModal() == .OK, let url = panel.url, let data = store.encoded() else { return }
        do {
            try data.write(to: url)
            importMsg = "선택지 \(store.total)개 내보냄 → \(url.lastPathComponent)"
        } catch {
            importMsg = "내보내기 실패: \(error.localizedDescription)"
        }
    }

    private func importShared() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(OptionsSnapshot.self, from: data) else {
            importMsg = "공유 파일을 읽지 못했습니다 (.json 형식 확인)."
            return
        }
        let added = store.merge(snap)
        importMsg = "공유 목록에서 \(added)개 새 선택지 추가됨"
    }

    private func linkSync() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "동기화할 공유 .json 파일을 고르세요. 없으면 먼저 '선택지 내보내기'로 만들어 두세요."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.linkSyncFile(url)
    }

    private var listsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(OptionStore.Field.allCases) { field in
                    listSection(field)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 360)
    }

    @ViewBuilder
    private func listSection(_ field: OptionStore.Field) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(field.rawValue)
                    .font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(.ink)
                Text("\(store.list(field).count)")
                    .font(.system(size: 11, design: .monospaced)).foregroundColor(.faint)
                Spacer()
            }

            let items = store.list(field)
            if items.isEmpty {
                Text("아직 없음 — 왼쪽에서 시트를 가져오거나 아래에 추가하세요.")
                    .font(.system(size: 11, design: .monospaced)).foregroundColor(.faint)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8, alignment: .leading)],
                          alignment: .leading, spacing: 8) {
                    ForEach(items, id: \.self) { v in chip(v, field) }
                }
            }

            AddInline { v, m in store.add(v, meaning: m, to: field) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.5))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.ink.opacity(0.12), lineWidth: 1))
    }

    private func chip(_ v: String, _ field: OptionStore.Field) -> some View {
        HStack(spacing: 5) {
            if let m = store.meaning(v) {
                Text(m).font(.system(size: 11, design: .monospaced)).foregroundColor(.ink).lineLimit(1)
                Text(v).font(.system(size: 10, design: .monospaced)).foregroundColor(.faint).lineLimit(1)
            } else {
                Text(v).font(.system(size: 11, design: .monospaced)).foregroundColor(.ink).lineLimit(1)
            }
            Button { store.remove(v, from: field) } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundColor(.faint)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.ink.opacity(0.06))
        .clipShape(Capsule())
        .help(store.meaning(v) == nil ? v : "\(store.meaning(v)!) (\(v))")
    }
}

/// Inline "add a value (+meaning)" row used inside each list section.
private struct AddInline: View {
    var onAdd: (String, String) -> Void
    @State private var draft = ""
    @State private var draftMeaning = ""

    var body: some View {
        HStack(spacing: 6) {
            TextField("값", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .padding(6)
                .background(Color.white.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.ink.opacity(0.15), lineWidth: 1))
                .onSubmit(submit)
            TextField("의미(선택)", text: $draftMeaning)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .padding(6)
                .background(Color.white.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.ink.opacity(0.15), lineWidth: 1))
                .onSubmit(submit)
            Button(action: submit) {
                Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundColor(.good)
            }
            .buttonStyle(.plain)
        }
    }

    private func submit() {
        let v = draft, m = draftMeaning
        draft = ""; draftMeaning = ""
        if !v.trimmingCharacters(in: .whitespaces).isEmpty { onAdd(v, m) }
    }
}
