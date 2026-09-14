import Foundation

public struct MealImageRequest: Equatable, Sendable {
    public let imageData: Data
    public let mimeType: String

    public init(imageData: Data, mimeType: String) {
        self.imageData = imageData
        self.mimeType = mimeType
    }

    public func validated(maxByteCount: Int = 2_000_000) throws -> Self {
        guard !imageData.isEmpty,
              imageData.count <= maxByteCount,
              ["image/jpeg", "image/heic"].contains(mimeType.lowercased()) else {
            throw MealAnalysisError.invalidImage
        }
        return self
    }
}

public struct DetectedFood: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let assumedPortion: String
    public let proteinGrams: Double
    public let confidence: Double

    public init(id: UUID = UUID(), name: String, assumedPortion: String, proteinGrams: Double, confidence: Double) {
        self.id = id
        self.name = name
        self.assumedPortion = assumedPortion
        self.proteinGrams = proteinGrams
        self.confidence = confidence
    }
}

public struct MealAnalysisResult: Codable, Equatable, Sendable {
    public let foods: [DetectedFood]
    public let totalProteinGrams: Double
    public let warnings: [String]

    public init(foods: [DetectedFood], totalProteinGrams: Double, warnings: [String] = []) {
        self.foods = foods
        self.totalProteinGrams = totalProteinGrams
        self.warnings = warnings
    }

    public func validated() throws -> EditableMealAnalysis {
        guard !foods.isEmpty else { throw MealAnalysisError.invalidResponse("No foods were detected.") }
        guard totalProteinGrams.isFinite, totalProteinGrams > 0 else { throw MealAnalysisError.invalidResponse("The total protein value is invalid.") }
        for food in foods {
            guard !food.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !food.assumedPortion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  food.proteinGrams.isFinite,
                  food.proteinGrams > 0,
                  food.proteinGrams <= ProteinEntryValidator.maximumGrams,
                  food.confidence.isFinite,
                  (0...1).contains(food.confidence) else {
                throw MealAnalysisError.invalidResponse("One or more detected foods are incomplete or outside allowed ranges.")
            }
        }
        let calculatedTotal = foods.reduce(0) { $0 + $1.proteinGrams }
        guard abs(calculatedTotal - totalProteinGrams) <= 0.5 else {
            throw MealAnalysisError.invalidResponse("The item values do not match the reported total.")
        }
        return EditableMealAnalysis(
            items: foods.map { .init(id: $0.id, name: $0.name, assumedPortion: $0.assumedPortion, proteinGrams: $0.proteinGrams, confidence: $0.confidence) },
            warnings: warnings.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        )
    }
}

public struct EditableMealItem: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var assumedPortion: String
    public var proteinGrams: Double
    public let confidence: Double
    public var isLowConfidence: Bool { confidence < 0.6 }

    public init(id: UUID = UUID(), name: String, assumedPortion: String, proteinGrams: Double, confidence: Double) {
        self.id = id
        self.name = name
        self.assumedPortion = assumedPortion
        self.proteinGrams = proteinGrams
        self.confidence = confidence
    }
}

public struct EditableMealAnalysis: Equatable, Sendable {
    public var items: [EditableMealItem]
    public let warnings: [String]
    public var totalProteinGrams: Double { items.reduce(0) { $0 + $1.proteinGrams } }
    public var hasLowConfidenceItems: Bool { items.contains(where: \.isLowConfidence) }

    public init(items: [EditableMealItem], warnings: [String]) {
        self.items = items
        self.warnings = warnings
    }

    public func entries(loggedAt: Date = .now) throws -> [ProteinEntry] {
        guard !items.isEmpty else { throw MealAnalysisError.invalidResponse("Add at least one food before saving.") }
        return try items.map { item in
            try ProteinEntryValidator.validate(name: item.name, grams: item.proteinGrams)
            guard !item.assumedPortion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MealAnalysisError.invalidResponse("Add an assumed portion for every food.")
            }
            return ProteinEntry(
                name: item.name.trimmingCharacters(in: .whitespacesAndNewlines),
                grams: item.proteinGrams,
                loggedAt: loggedAt,
                note: "Photo estimate reviewed by user · \(item.assumedPortion.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }
    }
}
