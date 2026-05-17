# Squad Team

> my-body

<!-- copilot-auto-assign: true -->

## Coordinator

| Name | Role | Notes |
|------|------|-------|
| Squad | Coordinator | Routes work, enforces handoffs and reviewer gates. |

## Members

| Name | Role | Charter | Status |
|------|------|---------|--------|
| 🏗️ Ripley | Lead / iOS Architect | `.squad/agents/ripley/charter.md` | active |
| ⚛️ Lambert | iOS UI Developer | `.squad/agents/lambert/charter.md` | active |
| 🔧 Ash | Core Engineer (Vision · HealthKit · CloudKit) | `.squad/agents/ash/charter.md` | active |
| 🧪 Parker | Tester / QA | `.squad/agents/parker/charter.md` | active |
| 🤖 @copilot | GitHub Coding Agent | `.github/copilot-instructions.md` (if present) | active |
| 📋 Scribe | Session Logger | `.squad/agents/scribe/charter.md` | active |
| 🔄 Ralph | Work Monitor | `.squad/agents/ralph/charter.md` | active |

### @copilot Capability Profile

| Capability | Rating | Notes |
|------------|--------|-------|
| Swift / SwiftUI implementation | 🟢 | Well-scoped UI tasks, components, view tweaks |
| SwiftData / data model changes | 🟡 | Acceptable if scope is clear; Ripley reviews |
| Vision / OCR parsing logic | 🟡 | Needs fixtures; pair with Parker tests |
| HealthKit / CloudKit / entitlements | 🔴 | Requires Ash — entitlements and provisioning are risky |
| Fastlane / release automation | 🔴 | Requires human review (signing, App Store) |
| Bug fixes with reproduction | 🟢 | Clear repro = good fit |
| Docs / README / comments | 🟢 | Strong fit |

Auto-assign: when an issue receives `squad:copilot`, @copilot picks it up. Lead (Ripley) triages all incoming `squad` labels and chooses the assignee.

## Issue Source

- **Repository:** `Jeff-Tian/my-body`
- **Connected:** 2026-05-15
- **Default branch:** `main`
- **Filters:** open issues, all labels

## Reference Docs (PRD-equivalent)

- `README.md` — product description, build commands, stack
- `docs/ocr-learning-roadmap.md` — OCR pipeline + self-learning phases
- `docs/i18n-roadmap.md` — localization plan
- `docs/release.md` — release process

## Project Context

- **Owner:** Jeff Tian
- **Project:** my-body (身记) — iOS app that scans the photo library for InBody body composition reports, extracts data via Vision OCR, persists with SwiftData, and writes to Apple Health. iCloud/Apple-Account sync is a planned future capability.
- **Stack:** Swift, SwiftUI, SwiftData, Swift Charts, Vision, PhotosUI, HealthKit, iOS 17+, xcodegen, fastlane
- **Universe:** Alien
- **Created:** 2026-05-15
