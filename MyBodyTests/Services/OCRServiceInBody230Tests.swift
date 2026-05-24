import XCTest
@testable import MyBody

/// Regression test for the InBody 230 axis-scale misread bug
/// (see `.squad/decisions.md → 2026-05-24` entry).
///
/// The source image is `IMG_2245.HEIC`. After desensitization, drop it at
/// `MyBodyTests/Fixtures/InBody/inbody230-sample-01.heic` and the test
/// activates automatically. While the fixture is missing, the test skips
/// with a clear message rather than failing — so this file can be checked
/// in and run on CI today.
final class OCRServiceInBody230Tests: XCTestCase {

    /// Filename Jeff drops into `MyBodyTests/Fixtures/InBody/`.
    /// `UIImage(contentsOfFile:)` accepts HEIC / JPG / PNG — match whatever
    /// extension the desensitized export uses.
    private static let fixtureBaseName = "inbody230-sample-01"
    private static let fixtureExtensionCandidates = ["heic", "HEIC", "jpg", "jpeg", "png"]

    /// Expected values for `IMG_2245.HEIC` (scan dated 2026-05-22).
    /// See `MyBodyTests/Fixtures/InBody/README.md` for the full table and
    /// the bug context.
    private let expectedWeight: Double = 68.1
    private let expectedSkeletalMuscle: Double = 31.7
    private let expectedBodyFatMass: Double = 12.0
    private let expectedTotalBodyWater: Double = 41.2
    private let expectedLeanBodyMass: Double = 56.1
    private let numericTolerance: Double = 0.05

    func test_parseReport_inbody230_axisScaleRegression() throws {
        let image = try loadFixtureImage()

        let service = OCRService()
        let parsed = try service.parseReport(from: image)

        XCTAssertEqual(parsed.weight ?? .nan, expectedWeight, accuracy: numericTolerance,
                       "weight misread — likely picked up axis scale instead of bar value")
        XCTAssertEqual(parsed.skeletalMuscle ?? .nan, expectedSkeletalMuscle, accuracy: numericTolerance,
                       "skeletalMuscle misread — likely picked up axis scale")
        XCTAssertEqual(parsed.bodyFatMass ?? .nan, expectedBodyFatMass, accuracy: numericTolerance,
                       "bodyFatMass misread — likely picked up axis scale")
        XCTAssertEqual(parsed.totalBodyWater ?? .nan, expectedTotalBodyWater, accuracy: numericTolerance,
                       "totalBodyWater misread — likely picked up axis scale")
        XCTAssertEqual(parsed.leanBodyMass ?? .nan, expectedLeanBodyMass, accuracy: numericTolerance,
                       "leanBodyMass misread — likely picked up axis scale")

        // Date is parsed off the full report text, not the bar chart, so it
        // is independent of the axis-scale bug — assert separately as a
        // sanity check that the rest of the pipeline still works.
        let date = try XCTUnwrap(parsed.scanDate, "scanDate should be parseable from report text")
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 5)
        XCTAssertEqual(comps.day, 22)
    }

    // MARK: - Fixture loading

    private func loadFixtureImage() throws -> UIImage {
        let bundle = Bundle(for: type(of: self))
        for ext in Self.fixtureExtensionCandidates {
            if let url = bundle.url(forResource: Self.fixtureBaseName, withExtension: ext),
               let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                return image
            }
        }
        throw XCTSkip("""
            Fixture not found. Drop the desensitized InBody 230 image at:
              MyBodyTests/Fixtures/InBody/\(Self.fixtureBaseName).heic
            See MyBodyTests/Fixtures/InBody/README.md for desensitization
            notes and expected values.
            """)
    }
}
