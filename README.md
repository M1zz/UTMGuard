# UTM Guard

A macOS app that stops UTM tracking links from breaking before they ship.

## Why this exists

Looking at the academy's campaign sheet, the recurring problems all came from
one root cause: people assembling UTM strings by hand. That produced:

- Casing drift — `Ig` / `ig` / `instagram` logged as three channels in GA
- Campaign typos — `roadshow-busan` vs `roadshow-busman` split one campaign in two
- Duplicate `utm_content` numbers inside a campaign — rows you can't tell apart
- Broken URLs — `https//` (missing colon), no scheme, `fasttrack2026//postech`
- Empty `utm_*` fields — clicks that log as "(not set)"
- Whole-URL vs component mismatch — two hand-typed copies of the same link drifting apart

## What it does

**Builder tab** — pick `utm_source` / `utm_medium` / `utm_campaign` from saved
choices (never free-typed, so casing drift and typos can't enter); each choice
shows its meaning, e.g. `인스타그램 (ig)`. `utm_content` auto-numbers to the next
free value in the campaign, so duplicates can't happen. The full URL is
*generated*, never typed, and the copy button is disabled while any error is
present — so a broken or colliding link can't leave.

**Sheet check tab** — paste your existing spreadsheet (with the header row).
Every problem row is flagged with the field, the reason in plain terms, and a
one-tap fix where one exists. One click also registers the sheet's values as
Builder choices.

**Lists tab** — manage the dropdown choices the Builder offers. Import them
straight from your working sheet (paste from Numbers, or open a CSV export); the
values you already use become the choices, and new ones you type are saved for
reuse. Export the lists to a single `.json` file and have teammates import it —
or **link** that file for real-time sync: changes are picked up automatically
(2-second poll, two-way), so the whole team shares one canonical vocabulary as
it grows. Put the file in Dropbox / Drive / a Git folder; no server or account
needed, and the link is restored on relaunch.

## Run it

1. Open `UTMGuard.xcodeproj` in Xcode 15+
2. Select the UTMGuard scheme, press Run (⌘R)
3. Requires macOS 14+

No dependencies, no signing setup needed for local runs.

## Files

- `UTMModel.swift` — the link model, sheet parser, canonical vocabulary
- `Validator.swift` — per-row and cross-row checks
- `BuilderView.swift` — the controlled-input builder
- `LinterView.swift` — the paste-and-audit view
- `OptionStore.swift` — saved dropdown choices, the Lists tab, and sheet/CSV import
