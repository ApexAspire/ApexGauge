import Foundation

/// Applies a watch payload (WatchConnectivity reply, userInfo or application
/// context) to the shared complication state and requests at most ONE timeline
/// reload per payload. Side effects are injected so the reload count can be
/// asserted in `swift test` without WidgetKit or WatchConnectivity.
public enum ComplicationPayloadApplier {
    /// - Parameters:
    ///   - setData: persists a Data value under a defaults key.
    ///   - setBool: persists a Bool value under a defaults key.
    ///   - writeSnapshot: persists validated snapshot bytes; returns false on failure.
    ///   - reload: requests a timeline reload; invoked at most once.
    /// - Returns: whether a reload was requested.
    @discardableResult
    public static func apply(
        _ payload: [String: Any],
        setData: (Data, String) -> Void,
        setBool: (Bool, String) -> Void,
        writeSnapshot: (Data) -> Bool,
        reload: () -> Void
    ) -> Bool {
        var changed = false

        if let data = payload[ApexGaugeDefaults.complicationWindowsKey] as? Data {
            setData(data, ApexGaugeDefaults.complicationWindowsKey)
            changed = true
        }

        if let data = payload[ApexGaugeDefaults.complicationHiddenProvidersKey] as? Data {
            setData(data, ApexGaugeDefaults.complicationHiddenProvidersKey)
            changed = true
        }

        if let displayPercentUsed = payload[ApexGaugeDefaults.watchDisplayModePayloadKey] as? Bool {
            setBool(displayPercentUsed, ApexGaugeDefaults.displayPercentUsedKey)
            changed = true
        }

        if let data = payload[ApexGaugeDefaults.watchSnapshotPayloadKey] as? Data,
           (try? JSONDecoder().decode(UsageSnapshot.self, from: data)) != nil,
           writeSnapshot(data) {
            changed = true
        }

        if changed { reload() }
        return changed
    }
}
