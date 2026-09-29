import Foundation
import MyinkCore
import Observation

/// The live settings. SwiftUI binds to `preferences`; AppKit subsystems register change handlers.
@Observable
final class SettingsStore {
    var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            preferences.save(to: defaults)
            for handler in handlers {
                handler(oldValue, preferences)
            }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var handlers: [(_ old: Preferences, _ new: Preferences) -> Void] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferences = Preferences.load(from: defaults)
    }

    func observe(_ handler: @escaping (_ old: Preferences, _ new: Preferences) -> Void) {
        handlers.append(handler)
    }
}
