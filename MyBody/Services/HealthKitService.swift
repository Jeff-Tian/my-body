import Foundation
import HealthKit

/// Testable seam for the Trends / Edit / Scan call paths that touch Apple Health.
///
/// Only the surface those call sites need is exposed — internals (queries, sample
/// construction, HKHealthStore) stay private on `HealthKitService`. Tests inject a
/// fake conforming to this protocol; production code keeps using `HealthKitService.shared`.
protocol HealthKitWriting {
    var isAvailable: Bool { get }
    var bodyMassWriteStatus: HKAuthorizationStatus { get }
    func requestAuthorization() async throws
    func writeWeightSamples(_ records: [InBodyRecord]) async throws -> HealthKitWriteResult
    func saveWeight(_ kg: Double, date: Date, recordID: UUID) async throws
}

/// 把识别出的体重写入「健康」App。
///
/// - 仅请求 `HKQuantityTypeIdentifier.bodyMass` 的写入/读取权限。
/// - 单例 `shared`，避免重复实例化 `HKHealthStore`。
/// - 用户在「设置」里关闭同步开关时，调用方应自行不再调用 `saveWeight`。
/// - 所有写入都附带 `HKMetadataKeySyncIdentifier`（key 为 `InBodyRecord.id.uuidString`），
///   重复调用同一条记录不会产生重复样本（同源内由 HealthKit 按 SyncVersion 替换）。
final class HealthKitService: HealthKitWriting {
    static let shared = HealthKitService()

    /// `HKHealthStore` 在不支持的设备（如 Mac Catalyst / iPad）上仍可创建，
    /// 但 `isHealthDataAvailable` 会返回 false。所有写入前都先检查它。
    private let store = HKHealthStore()

    private var bodyMassType: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: .bodyMass)
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// 当前 `bodyMass` 的写入授权状态。`sharingDenied` 时调用方应跳过写入并提示用户。
    var bodyMassWriteStatus: HKAuthorizationStatus {
        guard let bodyMass = bodyMassType else { return .notDetermined }
        return store.authorizationStatus(for: bodyMass)
    }

    /// 请求体重读写授权。iOS 不会暴露用户是否拒绝写入，因此只能在写入失败时
    /// 才能感知到拒绝；此处只负责把授权弹窗弹起来。
    func requestAuthorization() async throws {
        guard isAvailable, let bodyMass = bodyMassType else {
            throw HealthKitError.unavailable
        }
        try await store.requestAuthorization(toShare: [bodyMass], read: [bodyMass])
    }

    // MARK: - Single sample

    /// 向后兼容旧调用方：传入裸 weight + date，无 record.id 时不打 SyncIdentifier，
    /// 因此**无法去重**。新代码请用 `saveWeight(_:date:recordID:)`。
    func saveWeight(_ weightKg: Double, date: Date) async throws {
        try await writeWeightSample(weightKg: weightKg, date: date, syncIdentifier: nil)
    }

    /// 写入单条体重样本，按 `recordID.uuidString` 打 `HKMetadataKeySyncIdentifier`。
    /// 重复调用同一 recordID 不会产生重复样本（HK 同源内自动按 SyncVersion 替换）。
    /// 适合 ScanViewModel / EditRecordView 在 `Task.detached` 里调用 —— 参数都是 Sendable，
    /// 不需要把 SwiftData `@Model` 实例跨 actor 传递。
    func saveWeight(_ weightKg: Double, date: Date, recordID: UUID) async throws {
        try await writeWeightSample(
            weightKg: weightKg,
            date: date,
            syncIdentifier: recordID.uuidString
        )
    }

    /// 真正写入逻辑。`syncIdentifier` 非空时同时打上 `HKMetadataKeySyncIdentifier`
    /// + `HKMetadataKeySyncVersion = 1`，HealthKit 在同源内会自动按 SyncVersion 替换重复样本。
    private func writeWeightSample(
        weightKg: Double,
        date: Date,
        syncIdentifier: String?
    ) async throws {
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
        var metadata: [String: Any] = [
            HKMetadataKeyWasUserEntered: false  // OCR-derived, not manually entered
        ]
        if let sid = syncIdentifier {
            metadata[HKMetadataKeySyncIdentifier] = sid
            metadata[HKMetadataKeySyncVersion] = 1
        }
        let sample = HKQuantitySample(
            type: bodyMass,
            quantity: quantity,
            start: date,
            end: date,
            metadata: metadata
        )
        try await store.save(sample)
    }

    // MARK: - Batch write (Trends "写入健康" entry point)

    /// 批量把 `InBodyRecord` 的体重写入「健康」。
    ///
    /// 行为：
    /// 1. 预检 `isAvailable` + 授权（`.notDetermined` 一次性弹窗），失败抛 `HealthKitError`。
    /// 2. 过滤无效输入（weight nil / <= 0 / 未来日期）→ 累加到 `skippedInvalid`。
    /// 3. 查询本 app 已写入的样本，按 `HKMetadataKeySyncIdentifier` 比对 → `skippedDuplicate`。
    /// 4. 剩余样本批量 `save`，每条带 `HKMetadataKeySyncIdentifier = record.id.uuidString`
    ///    + `HKMetadataKeySyncVersion = 1`。即使第 3 步漏掉（竞态），HK 也会按 SyncVersion 自动去重。
    /// 5. 全程不抛单条错误；失败信息聚合到 `result.failed`。
    ///
    /// 实现说明：选择「query-first + 写入时也带 SyncIdentifier」的双保险路径，原因：
    /// - HK 的 `save([HKObject])` 在 SyncIdentifier 冲突时是「替换」语义，不会单独报告
    ///   有多少条被替换；为了能给用户看到「跳过 X 条重复」，必须自己 query 先数一遍。
    /// - 同时保留 SyncIdentifier 是因为 query→save 之间的竞态（或我们的查询遗漏）
    ///   仍然可能导致重复，HK 的版本化替换提供最后一道防线。
    ///
    /// - Returns: 写入统计。**只在预检失败时抛错**（设备不支持 / 授权被拒）。
    func writeWeightSamples(_ records: [InBodyRecord]) async throws -> HealthKitWriteResult {
        guard isAvailable, let bodyMass = bodyMassType else {
            throw HealthKitError.unavailable
        }

        var result = HealthKitWriteResult()

        // 1) 先在调用者 actor 上把 SwiftData `@Model` 读成 Sendable 原语，
        //    避免后续 await 之后再触碰 model 导致跨 actor 隔离问题。
        struct Candidate { let id: UUID; let weight: Double; let date: Date }
        let parts = Self.partitionForWrite(records)
        result.skippedInvalid = parts.skippedInvalid.count
        let candidates: [Candidate] = parts.writable.compactMap { record in
            guard let w = record.weight else { return nil }
            return Candidate(id: record.id, weight: w, date: record.scanDate)
        }

        // 2) Pre-flight 授权：一次性 prompt，避免循环里多次询问。
        switch store.authorizationStatus(for: bodyMass) {
        case .sharingDenied:
            throw HealthKitError.notAuthorized
        case .notDetermined:
            try await store.requestAuthorization(toShare: [bodyMass], read: [bodyMass])
            // 用户拒绝时 iOS 不抛错，只能再查一次状态确认。
            if store.authorizationStatus(for: bodyMass) == .sharingDenied {
                throw HealthKitError.notAuthorized
            }
        case .sharingAuthorized:
            break
        @unknown default:
            break
        }

        guard !candidates.isEmpty else { return result }

        // 3) 查询已写入：只看本 app 写入的样本，匹配 SyncIdentifier。
        let candidateIDs = Set(candidates.map { $0.id.uuidString })
        let existingIDs = await queryExistingSyncIdentifiers(
            type: bodyMass,
            among: candidateIDs
        )

        // 4) 构造样本并批量保存
        var toSave: [HKQuantitySample] = []
        var sampleToRecordID: [ObjectIdentifier: UUID] = [:]
        for c in candidates {
            let sid = c.id.uuidString
            if existingIDs.contains(sid) {
                result.skippedDuplicate += 1
                continue
            }
            let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: c.weight)
            let metadata: [String: Any] = [
                HKMetadataKeyWasUserEntered: false,
                HKMetadataKeySyncIdentifier: sid,
                HKMetadataKeySyncVersion: 1
            ]
            let sample = HKQuantitySample(
                type: bodyMass,
                quantity: quantity,
                start: c.date,
                end: c.date,
                metadata: metadata
            )
            toSave.append(sample)
            sampleToRecordID[ObjectIdentifier(sample)] = c.id
        }

        guard !toSave.isEmpty else { return result }

        // 一次性 save。HKHealthStore.save([HKObject]) 是原子的；任何一条违规整批回滚。
        // 出错时退化为逐条写入，把失败定位到具体 record。
        do {
            try await store.save(toSave)
            result.written = toSave.count
        } catch {
            for sample in toSave {
                guard let recordID = sampleToRecordID[ObjectIdentifier(sample)] else { continue }
                do {
                    try await store.save(sample)
                    result.written += 1
                } catch {
                    result.failed.append((recordID: recordID, error: error))
                }
            }
        }

        return result
    }

    /// 查询当前 source 已写入的样本里，SyncIdentifier 落在 `wanted` 集合的子集。
    /// 用于批量写入前判断哪些 record 已经写过。返回的 ID 字符串集合即 `record.id.uuidString`。
    private func queryExistingSyncIdentifiers(
        type: HKQuantityType,
        among wanted: Set<String>
    ) async -> Set<String> {
        // 仅查询本 app 自己写入的样本，避免误把其它 app 的体重当成已存在。
        let sourcePredicate = HKQuery.predicateForObjects(from: HKSource.default())

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: sourcePredicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                guard let samples = samples else {
                    continuation.resume(returning: [])
                    return
                }
                var found: Set<String> = []
                for sample in samples {
                    if let sid = sample.metadata?[HKMetadataKeySyncIdentifier] as? String,
                       wanted.contains(sid) {
                        found.insert(sid)
                    }
                }
                continuation.resume(returning: found)
            }
            store.execute(query)
        }
    }

    // MARK: - Pre-flight partition (shared with tests)

    /// 把候选记录拆成「可写入」和「应跳过（无效）」两组。
    /// 无效定义：`weight == nil` / `<= 0` / `scanDate > now`。
    /// 提取为 `static` 以便测试 Fake (`FakeHealthKitWriter`) 重用同一份过滤逻辑，
    /// 避免 production 行为与测试 mirror 漂移。
    /// `now` 可注入以便测试控制「未来日期」判定边界，默认 `Date()`。
    static func partitionForWrite(
        _ records: [InBodyRecord],
        now: Date = Date()
    ) -> (writable: [InBodyRecord], skippedInvalid: [InBodyRecord]) {
        var writable: [InBodyRecord] = []
        var skipped: [InBodyRecord] = []
        for r in records {
            if let w = r.weight, w > 0, r.scanDate <= now {
                writable.append(r)
            } else {
                skipped.append(r)
            }
        }
        return (writable, skipped)
    }
}

// MARK: - Result types

/// 批量写入结果，供 UI 详细对话框展示「写入 X / 跳过重复 Y / 跳过无效 Z / 失败 N」。
struct HealthKitWriteResult: Sendable {
    var written: Int = 0
    /// 因 `weight == nil` / `<= 0` / 未来日期被跳过。
    var skippedInvalid: Int = 0
    /// 已写入过同一 `record.id`（按 SyncIdentifier 判定），本次跳过。
    var skippedDuplicate: Int = 0
    /// 每条样本级失败的 (record.id, error) 列表。预检失败不会进这里（会抛错）。
    var failed: [(recordID: UUID, error: Error)] = []

    var totalProcessed: Int { written + skippedInvalid + skippedDuplicate + failed.count }
    var failedCount: Int { failed.count }
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
