import SwiftData

public enum PersistenceController {
    public static let schema = Schema([
        ProteinEntry.self,
        SavedMeal.self,
        UserSettings.self
    ])

    public static func makeShared() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "Protein",
            schema: schema,
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    public static func makeInMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "ProteinTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
