import SwiftUI
import Photos

@main
struct PhotoShareServerApp: App {
    @StateObject private var serverManager = ServerManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(serverManager)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        
        MenuBarExtra("PhotoShare", systemImage: serverManager.isRunning ? "photo.circle.fill" : "photo.circle") {
            MenuBarView()
                .environmentObject(serverManager)
        }
    }
}

