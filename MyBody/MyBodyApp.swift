import SwiftUI
import SwiftData

@main
struct MyBodyApp: App {
    let sharedContainer: ModelContainer = {
        do {
            let container = try ModelContainer(for: InBodyRecord.self, OCRCorrection.self)
            ScreenshotSampleData.seedIfNeeded(container: container)
            return container
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedContainer)
    }
}
