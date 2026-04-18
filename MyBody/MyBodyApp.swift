import SwiftUI
import SwiftData

@main
struct MyBodyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: InBodyRecord.self)
    }
}
