import Foundation
import Combine

final class SettingsViewModel: ObservableObject {
    var settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }
}
