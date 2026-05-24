import XCTest
@testable import MyBody

/// 诊断工具:把 InBody 230 固定样张的原始 OCR 观测全部打印出来,
/// 用于回归调参 / 排查"OCR 看到什么 vs 解析挑了什么"两端的偏差。
///
/// 行为约定:
///   - **不做任何 XCTAssert**,只 print,绝不让测试套件挂掉。
///   - 缺少 fixture 时直接 XCTSkip,与回归测试一致。
///   - 默认走 `make test-unit` 也会执行(快,日志多但不会污染 CI 通过率);
///     若日志过吵,设环境变量 `OCR_SKIP_DUMP=1` 跳过。
final class OCRServiceInBody230DumpTests: XCTestCase {

    private static let fixtureBaseName = "inbody230-sample-01"
    private static let fixtureExtensionCandidates = ["heic", "HEIC", "jpg", "jpeg", "png"]

    func test_dump_inbody230_rawOCR() throws {
        if ProcessInfo.processInfo.environment["OCR_SKIP_DUMP"] == "1" {
            throw XCTSkip("OCR_SKIP_DUMP=1 — skipping diagnostic dump")
        }
        let image = try loadFixtureImage()
        let service = OCRService()

        // 1) 取出 Vision 全部原始 boxes(已含同义预处理逻辑)
        let boxes = try service.recognizeBoxes(from: image)

        // 2) 全量打印 — 按 cy 降序(图像顶部 cy≈1.0),同 cy 再按 cx 升序
        let sorted = boxes.sorted { a, b in
            if abs(a.cy - b.cy) < 0.005 { return a.cx < b.cx }
            return a.cy > b.cy
        }

        print("\n========== InBody230 RAW OCR DUMP (\(sorted.count) boxes) ==========")
        print("text | cx | cy | w | h")
        for b in sorted {
            let safe = b.text.replacingOccurrences(of: "\n", with: "⏎")
            let row = String(
                format: "%@ | cx=%.3f cy=%.3f w=%.3f h=%.3f",
                safe,
                Double(b.cx), Double(b.cy), Double(b.box.width), Double(b.box.height)
            )
            print(row)
        }
        print("=========================================================\n")

        // 3) 针对每个有问题的字段,打印 label 行 + 同行候选 + 评分胜出者
        let targets: [(name: String, keys: [String])] = [
            ("weight",         ["体重", "Weight"]),
            ("bodyFatMass",    ["体脂肪量", "体脂肪", "Body Fat Mass", "BFM"]),
            ("totalBodyWater", ["身体水分总量", "身体水分", "体水分", "Total Body Water", "TBW"]),
            ("leanBodyMass",   ["去脂体重", "瘦体重", "Lean Body Mass", "LBM", "FFM"]),
            ("skeletalMuscle", ["骨骼肌量", "骨骼肌", "Skeletal Muscle", "SMM"])
        ]

        let report = service.parseBoxes(boxes)
        for t in targets {
            print("---- field: \(t.name) ----")
            // 找到所有 label box
            let labels = boxes.filter { box in
                t.keys.contains(where: { key in
                    box.text.replacingOccurrences(of: " ", with: "")
                        .range(of: key, options: .caseInsensitive) != nil
                })
            }
            if labels.isEmpty {
                print("  [no label matched for keys=\(t.keys)]")
            }
            for label in labels {
                let rowTol = max(label.box.height, 0.012) * 1.8
                print(String(
                    format: "  LABEL '%@' cx=%.3f cy=%.3f h=%.3f rowTol=±%.3f",
                    label.text, Double(label.cx), Double(label.cy),
                    Double(label.box.height), Double(rowTol)
                ))
                let sameRow = boxes
                    .filter { $0.left > label.right - 0.005 }
                    .filter { abs($0.cy - label.cy) < rowTol }
                    .sorted { $0.cx < $1.cx }
                if sameRow.isEmpty { print("    (no same-row candidates to the right)") }
                for cand in sameRow {
                    print(String(
                        format: "    cand '%@' cx=%.3f cy=%.3f w=%.3f h=%.3f",
                        cand.text, Double(cand.cx), Double(cand.cy),
                        Double(cand.box.width), Double(cand.box.height)
                    ))
                }
            }
            let parsed: Double? = {
                switch t.name {
                case "weight":         return report.weight
                case "bodyFatMass":    return report.bodyFatMass
                case "totalBodyWater": return report.totalBodyWater
                case "leanBodyMass":   return report.leanBodyMass
                case "skeletalMuscle": return report.skeletalMuscle
                default: return nil
                }
            }()
            let raw = report.rawTexts[t.name] ?? "(nil)"
            print("  >>> parser picked: value=\(parsed.map { String($0) } ?? "nil") rawText='\(raw)'")
        }
        print("=========================================================\n")
    }

    private func loadFixtureImage() throws -> UIImage {
        // Diagnostic override: when `OCR_DUMP_IMAGE_PATH` is set, load that
        // file directly off the local filesystem. Used for one-off diagnosis
        // against the original (PII-bearing) source photo without committing
        // it. This branch MUST NOT be relied on by CI.
        if let overridePath = ProcessInfo.processInfo.environment["OCR_DUMP_IMAGE_PATH"],
           !overridePath.isEmpty {
            let url = URL(fileURLWithPath: overridePath)
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else {
                throw XCTSkip("OCR_DUMP_IMAGE_PATH set but image could not be loaded: \(overridePath)")
            }
            print("⚙️  Using OCR_DUMP_IMAGE_PATH override: \(overridePath)")
            return image
        }

        let bundle = Bundle(for: type(of: self))
        for ext in Self.fixtureExtensionCandidates {
            if let url = bundle.url(forResource: Self.fixtureBaseName, withExtension: ext),
               let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                return image
            }
        }
        throw XCTSkip("Fixture not found at MyBodyTests/Fixtures/InBody/\(Self.fixtureBaseName).heic")
    }
}
