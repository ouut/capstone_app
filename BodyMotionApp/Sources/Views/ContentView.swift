import SwiftUI

struct ContentView: View {
    @StateObject private var settings = AppSettings()

    var body: some View {
        TabView {
            CaptureView(viewModel: CaptureViewModel(settings: settings))
                .tabItem {
                    Label("Capture", systemImage: "camera.viewfinder")
                }

            SettingsView(viewModel: SettingsViewModel(settings: settings))
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}
