import Foundation
import HealthKit

/// 把识别出的体重写入「健康」App。
///
/// - 仅请求 `HKQuantityTypeIdentifier.bodyMass` 的写入权限（以及为了校验同步结果
///   而附带的读取权限），不读取/写入其他健康数据。
/// - 单例 `shared`，避免重复实例化 `HKHealthStore`。
/// - 用户在「设置」里关闭同步开关时，调用方应自行不再调用 `saveWeight`。
final class HealthKitService {
    static let shared = HealthKitService()

    /// `HKHealthStore` 在不支持的设备（如 Mac Catalyst / iPad）上仍可创建，
    /// 但 `isHealthDataAvailable` 会返回 false。所有写入前都先检查它。
    private let store = HKHealthStore()

    private var bodyMassType: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: .bodyMass)
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// 请求体重读写授权。iOS 不会暴露用户是否拒绝写入，因此只能在写入失败时
    /// 才能感知到拒绝；此处只负责把授权弹窗弹起来。
    func requestAuthorization() async throws {
        guard isAvailable, let bodyMass = bodyMassType else {
            throw HealthKitError.unavailable
        }
        try await store.requestAuthorization(toShare: [bodyMass], read: [bodyMass])
    }

    /// 写入一条体重样本。
    /// - Parameters:
    ///   - weightKg: 体重，单位 kg。<= 0 视为无效，不写入。
    ///   - date: 测量时间。建议传 `InBodyRecord.scanDate`。
    /// - Throws: 设备不支持、未授权或底层 HealthKit 错误。
    func saveWeight(_ weightKg: Double, date: Date) async throws {
        guard isAvailable, let bodyMass = bodyMassType else {
            throw HealthKitError.unavailable
        }
        guard weightKg > 0 else { throw HealthKitError.invalidValue }

        // 写入前再检查一次授权状态。`.notDetermined` 时主动弹窗，避免静默失败。
        switch store.authorizationStatus(for: bodyMass) {
        case .sharingDenied:
            throw HealthKitError.notAuthorized
        case .notDetermined:
            try await store.requestAuthorization(toShare: [bodyMass], read: [bodyMass])
        case .sharingAuthorized:
            break
        @unknown default:
            break
        }

        let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: weightKg)
        let sample = HKQuantitySample(
            type: bodyMass,
            quantity: quantity,
            start: date,
            end: date,
            metadata: [HKMetadataKeyWasUserEntered: true]
        )
        try await store.save(sample)
    }
}

enum HealthKitError: LocalizedError {
    case unavailable
    case notAuthorized
    case invalidValue

    var errorDescription: String? {
        switch self {
        case .unavailable: return "当前设备不支持「健康」App"
        case .notAuthorized: return "未授权写入「健康」"
        case .invalidValue: return "体重数值无效"
        }
    }
}
