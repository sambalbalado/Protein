import Foundation

public enum AppGroup {
    public static var identifier: String {
        Bundle.main.object(forInfoDictionaryKey: "ProteinAppGroupIdentifier") as? String
            ?? "group.com.example.Protein"
    }
    public static let todayProteinKey = "todayProteinGrams"

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
