import SwiftUI

@main
struct StarWishArchiveApp: App {
    @StateObject private var store = ArchiveStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
