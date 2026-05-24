# InBody OCR Regression Fixtures

This directory holds desensitized InBody screenshots used as regression
fixtures for [`OCRService.parseReport`](../../../MyBody/Services/OCRService.swift).

## How to add the IMG_2245 (axis-scale misread) fixture

1. **Desensitize the source image** (`IMG_2245.HEIC`):
   - Blur or redact the ID number at the top-left (`13061910273`).
   - Blur or redact any name/phone/QR code if visible.
   - Body metric numbers and the chart axis scales **must remain legible** —
     they are the data under test.
2. **Save the image as** `inbody230-sample-01.heic` (preserve HEIC if you can;
   `.jpg` / `.png` also work — `UIImage` accepts all three).
3. **Drop the file into this directory**:

   ```
   MyBodyTests/Fixtures/InBody/inbody230-sample-01.heic
   ```

4. **Add it to the `MyBodyTests` target's `Resources` build phase**
   (XcodeGen handles this automatically once the target exists; see below).

That's it. After regenerating the project, run the test target and
`OCRServiceInBody230Tests` will exercise the parser end-to-end.

## Expected parse results (from `IMG_2245.HEIC`, scan dated 2026-05-22)

The fixture should produce a `ParsedReport` matching these values
(within a small numeric tolerance to allow for OCR drift):

| Field            | Expected | Tolerance | Notes                                     |
|------------------|----------|-----------|-------------------------------------------|
| `scanDate`       | 2026-05-22 | day match | Parsed by `extractDate` from full text   |
| `weight`         | 68.1 kg  | ±0.05     | Currently misread as 75.0 (axis scale)    |
| `skeletalMuscle` | 31.7 kg  | ±0.05     | Currently misread as 40.0                 |
| `bodyFatMass`    | 12.0 kg  | ±0.05     | Currently misread as 30.0                 |
| `totalBodyWater` | 41.2 kg  | ±0.05     | Currently misread as 50.0                 |
| `leanBodyMass`   | 56.1 kg  | ±0.05     | Currently misread as 80.0                 |

See [.squad/decisions.md → "InBody 横向柱状图坐标轴刻度被误读"](../../../.squad/decisions.md)
for the root-cause analysis. This fixture **will fail today** — it is the
regression target for the upcoming `findValue` scoring fix (Plan A).

### Not currently parsed (out of scope for this fixture)

The visible report also contains `height=169 cm`, `age=41`, `gender=男`.
`ParsedReport` does not currently surface these fields, so the test does
not assert them. If the parser later adds them, extend
[`OCRServiceInBody230Tests`](../Services/OCRServiceInBody230Tests.swift).

## ⚠️ Required project setup — add `MyBodyTests` target

The repo currently only has `MyBodyUITests` (UI testing bundle). To run
the unit test stub at
[`MyBodyTests/Services/OCRServiceInBody230Tests.swift`](../Services/OCRServiceInBody230Tests.swift),
add the following target to [`project.yml`](../../project.yml) under
`targets:` (alongside `MyBody` and `MyBodyUITests`):

```yaml
  MyBodyTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: MyBodyTests
    dependencies:
      - target: MyBody
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: brickverse.MyBodyAppTests
        DEVELOPMENT_TEAM: "${DEVELOPMENT_TEAM}"
        CODE_SIGN_STYLE: Automatic
        SWIFT_VERSION: "5.9"
        TARGETED_DEVICE_FAMILY: "1"
        GENERATE_INFOPLIST_FILE: YES
        BUNDLE_LOADER: "$(TEST_HOST)"
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/身记.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/身记"
```

Then also extend the `MyBody` scheme so `xcodebuild test` runs it:

```yaml
schemes:
  MyBody:
    build:
      targets:
        MyBody: all
        MyBodyTests: [test]            # ← add
        MyBodyUITests: [test]
    test:
      config: Debug
      targets:
        - MyBodyTests                  # ← add (run before UI tests; faster)
        - MyBodyUITests
```

After editing `project.yml`, regenerate the Xcode project:

```sh
make project   # or: xcodegen generate
```
