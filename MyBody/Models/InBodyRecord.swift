import Foundation
import SwiftData

@Model
final class InBodyRecord {
    var id: UUID
    var scanDate: Date
    var scanTime: String?

    // MARK: - Body Composition
    var weight: Double?
    var skeletalMuscle: Double?
    var bodyFatMass: Double?
    var totalBodyWater: Double?
    var leanBodyMass: Double?

    // MARK: - Obesity Analysis
    var bmi: Double?
    var bodyFatPercent: Double?
    var whr: Double?

    // MARK: - Other Metrics
    var bmr: Double?
    var inbodyScore: Int?
    var visceralFatLevel: Int?
    var dailyCalorie: Double?

    // MARK: - Segmental Muscle (kg)
    var segMuscleLeftArm: Double?
    var segMuscleRightArm: Double?
    var segMuscleTrunk: Double?
    var segMuscleLeftLeg: Double?
    var segMuscleRightLeg: Double?

    // MARK: - Segmental Fat (%)
    var segFatLeftArm: Double?
    var segFatRightArm: Double?
    var segFatTrunk: Double?
    var segFatLeftLeg: Double?
    var segFatRightLeg: Double?

    // MARK: - Photo
    @Attribute(.externalStorage) var photoData: Data?
    var photoAssetIdentifier: String?

    var createdAt: Date

    init(
        id: UUID = UUID(),
        scanDate: Date = Date(),
        scanTime: String? = nil,
        weight: Double? = nil,
        skeletalMuscle: Double? = nil,
        bodyFatMass: Double? = nil,
        totalBodyWater: Double? = nil,
        leanBodyMass: Double? = nil,
        bmi: Double? = nil,
        bodyFatPercent: Double? = nil,
        whr: Double? = nil,
        bmr: Double? = nil,
        inbodyScore: Int? = nil,
        visceralFatLevel: Int? = nil,
        dailyCalorie: Double? = nil,
        segMuscleLeftArm: Double? = nil,
        segMuscleRightArm: Double? = nil,
        segMuscleTrunk: Double? = nil,
        segMuscleLeftLeg: Double? = nil,
        segMuscleRightLeg: Double? = nil,
        segFatLeftArm: Double? = nil,
        segFatRightArm: Double? = nil,
        segFatTrunk: Double? = nil,
        segFatLeftLeg: Double? = nil,
        segFatRightLeg: Double? = nil,
        photoData: Data? = nil,
        photoAssetIdentifier: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.scanDate = scanDate
        self.scanTime = scanTime
        self.weight = weight
        self.skeletalMuscle = skeletalMuscle
        self.bodyFatMass = bodyFatMass
        self.totalBodyWater = totalBodyWater
        self.leanBodyMass = leanBodyMass
        self.bmi = bmi
        self.bodyFatPercent = bodyFatPercent
        self.whr = whr
        self.bmr = bmr
        self.inbodyScore = inbodyScore
        self.visceralFatLevel = visceralFatLevel
        self.dailyCalorie = dailyCalorie
        self.segMuscleLeftArm = segMuscleLeftArm
        self.segMuscleRightArm = segMuscleRightArm
        self.segMuscleTrunk = segMuscleTrunk
        self.segMuscleLeftLeg = segMuscleLeftLeg
        self.segMuscleRightLeg = segMuscleRightLeg
        self.segFatLeftArm = segFatLeftArm
        self.segFatRightArm = segFatRightArm
        self.segFatTrunk = segFatTrunk
        self.segFatLeftLeg = segFatLeftLeg
        self.segFatRightLeg = segFatRightLeg
        self.photoData = photoData
        self.photoAssetIdentifier = photoAssetIdentifier
        self.createdAt = createdAt
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: scanDate)
    }

    var formattedDateTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        if let time = scanTime {
            return "\(formattedDate) \(time)"
        }
        return formatter.string(from: scanDate)
    }
}
