import Foundation

/// User-configurable tablet-area mapping, persisted across launches.
///
/// Width/height directly define the active tracking rectangle, in iPad
/// points, centered on screen — there's no separate "sensitivity" knob:
/// a smaller area naturally means less physical movement to cover the full
/// logical range, which *is* sensitivity. The ratio lock is a pure editing
/// convenience: with it on, changing one dimension derives the other from
/// the locked ratio, so only one field needs adjusting at a time.
struct TabletSettings {
    static let didChangeNotification = Notification.Name("TabletSettingsDidChange")

    static var aspectRatioLocked: Bool {
        get { UserDefaults.standard.object(forKey: "aspectRatioLocked") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "aspectRatioLocked") }
    }

    /// Locked width:height ratio, e.g. 1.4 for a squarer feel than the
    /// screen's native rectangle.
    static var aspectRatio: Double {
        get { UserDefaults.standard.object(forKey: "aspectRatio") as? Double ?? (activeWidth / activeHeight) }
        set { UserDefaults.standard.set(newValue, forKey: "aspectRatio") }
    }

    static var activeWidth: Double {
        get { UserDefaults.standard.object(forKey: "activeWidth") as? Double ?? 1024 }
        set { UserDefaults.standard.set(newValue, forKey: "activeWidth") }
    }

    static var activeHeight: Double {
        get { UserDefaults.standard.object(forKey: "activeHeight") as? Double ?? 768 }
        set { UserDefaults.standard.set(newValue, forKey: "activeHeight") }
    }

    /// Active area's displacement from screen center, in points. Adjusted by
    /// dragging the area on screen with a finger.
    static var offsetX: Double {
        get { UserDefaults.standard.object(forKey: "offsetX") as? Double ?? 0 }
        set { UserDefaults.standard.set(newValue, forKey: "offsetX") }
    }

    static var offsetY: Double {
        get { UserDefaults.standard.object(forKey: "offsetY") as? Double ?? 0 }
        set { UserDefaults.standard.set(newValue, forKey: "offsetY") }
    }

    /// 0 = raw passthrough (default). Higher values exponentially average
    /// consecutive samples, trading latency/responsiveness for less jitter.
    /// Clamped below 1.0 so the filter can't freeze entirely.
    static var smoothing: Double {
        get { min(UserDefaults.standard.object(forKey: "smoothing") as? Double ?? 0.0, 0.95) }
        set { UserDefaults.standard.set(min(max(newValue, 0.0), 0.95), forKey: "smoothing") }
    }

    /// Seeds width/height/ratio from the device's real screen size on first
    /// launch only, so the default is a correct 1:1 full-screen mapping
    /// instead of a guessed constant.
    static func seedDefaultsIfNeeded(width: Double, height: Double) {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "activeWidth") == nil else { return }
        defaults.set(width, forKey: "activeWidth")
        defaults.set(height, forKey: "activeHeight")
        defaults.set(width / height, forKey: "aspectRatio")
    }

    static func notifyChanged() {
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}
