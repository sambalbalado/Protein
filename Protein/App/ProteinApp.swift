import ProteinCore
import SwiftData
import SwiftUI

@main
struct ProteinApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try PersistenceController.makeShared()
        } catch {
            fatalError("Unable to initialize Protein's local store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ProteinRootView()
        }
        .modelContainer(modelContainer)
    }
}
