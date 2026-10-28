import CreatorGeometry
import Foundation

/// Where the last length unit the person chose is remembered between launches, so a new document starts in it (DIM-1,
/// spec §6). Injected into `AppModel`, so tests never touch the real defaults: the app uses `UserDefaultsUnitPreference`,
/// tests `InMemoryUnitPreference`.
@MainActor
public protocol UnitPreference: AnyObject {
    var lastLength: LengthUnit { get set }
}

/// A preference that lives as long as the object; what tests and a bare `AppModel` use. Starts in millimetres.
@MainActor
public final class InMemoryUnitPreference: UnitPreference {
    public var lastLength: LengthUnit

    public init(lastLength: LengthUnit = .millimetres) {
        self.lastLength = lastLength
    }
}

/// The last unit in the person's defaults. The app passes `.standard`; tests pass a suite of their own and remove it.
@MainActor
public final class UserDefaultsUnitPreference: UnitPreference {
    /// The defaults key.
    public static let key = "MetalCreator.lastLengthUnit"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Millimetres until a unit is chosen, and for a stored value that is not a unit.
    public var lastLength: LengthUnit {
        get { defaults.string(forKey: Self.key).flatMap(LengthUnit.init(rawValue:)) ?? .millimetres }
        set { defaults.set(newValue.rawValue, forKey: Self.key) }
    }
}
