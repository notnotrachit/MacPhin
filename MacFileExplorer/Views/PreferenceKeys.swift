import SwiftUI

// Preference key to collect the frames of items inside the file list.
struct ItemFramePreferenceKey: PreferenceKey {
    typealias Value = [UUID: CGRect]

    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        let next = nextValue()
        // Only merge if there are actually new values to avoid unnecessary updates
        if !next.isEmpty {
            value.merge(next, uniquingKeysWith: { $1 })
        }
    }
}
