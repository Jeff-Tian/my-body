# Squad Decisions

## Active Decisions

### 2026-05-24T00:00:00Z: Single-photo import entry point on HomeView FAB
**By:** Lambert (iOS UI Developer)
**What:** Added a "选择单张照片" option to the HomeView "导入报告" FAB via a `Menu`. New `SinglePhotoImportView` runs one picker-selected photo through `ScanViewModel.startSingleImport`, which has a dual code path: PHAsset fast path (reuses batch pipeline, preserves dedup) and raw `Data` fallback (saves with `assetIdentifier: nil` when PHAsset access is limited).
**Why:**
- **Menu over confirmation dialog / inline twin buttons:** keeps the FAB visually unchanged ("导入报告" + icon), discoverable without crowding the home screen; menu items have icons so the choice is obvious.
- **Dual-path (PHAsset + Data) instead of single Data-only flow:** `PhotosPicker(photoLibrary: .shared())` exposes PHAsset `localIdentifier` via `itemIdentifier`, so picker-selected photos can flow through the same dedup-aware pipeline as full-library scans. The Data fallback only kicks in when the identifier is missing (limited-access album), where dedup isn't possible anyway. Net result: same import experience whether the user scans the library or hand-picks one photo, with no schema or service changes.
- **New sibling view instead of modifying PhotoScanView:** keeps batch-scan UI / state machine intact (no risk to existing flow); `SinglePhotoImportView` mirrors only the `parsingView` portion needed for one-shot import.

**Files touched:**
- `MyBody/Views/Home/HomeView.swift` — Menu FAB + PhotosPicker + sheet wiring
- `MyBody/ViewModels/ScanViewModel.swift` — `startSingleImport(itemIdentifier:fallbackImageData:)` + `parseSingleDataImage`
- `MyBody/Views/Scan/SinglePhotoImportView.swift` — new view (sheet host for single-import parsing UI)

**Verified:** `xcodebuild ... build CODE_SIGNING_ALLOWED=NO` succeeded (only pre-existing OCR deprecation warnings).

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction
