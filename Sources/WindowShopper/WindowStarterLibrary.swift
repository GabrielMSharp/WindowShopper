import Foundation

public extension WindowLibrary {
    /// Legacy starters, themed wall elevations and dressed room variations. Existing
    /// photographic starters already contain furnishings; do not duplicate them
    /// with matching layers. Dressed variants use shared RGBA props and treatments.
    static func starter() throws -> WindowLibrary {
        guard let url=Bundle.module.url(forResource:"WindowPresets",withExtension:"json") else {
            throw WindowValidationError.invalid("library","Missing starter presets")
        }
        let library=try JSONDecoder().decode(WindowLibrary.self,from:Data(contentsOf:url))
        try library.validate(); return library
    }
    static var starterResourceRoot: URL { Bundle.module.resourceURL! }
}
