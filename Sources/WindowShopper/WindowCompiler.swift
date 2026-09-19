import Foundation
import RealityKit

/// Turns saved component recipes into renderable geometry/materials. Call on an
/// exported scene copy; the caller then writes a new compiled .reality archive.
/// It never changes an RCP project or the shared preset library.
@MainActor public enum WindowCompiler {
    @discardableResult public static func compile(in root: Entity, library: WindowLibrary,
            resources: WindowResources, resourceRoot: URL) async throws -> Int {
        try library.validate()
        var targets: [(Entity,WindowComponent)] = []
        func collect(_ e: Entity) {
            if let component=e.components[WindowComponent.self] {targets.append((e,component));return}
            for child in e.children {collect(child)}
        }
        collect(root)
        guard Set(targets.map{$0.1.id}).count == targets.count,
              targets.allSatisfy({!$0.1.id.isEmpty}) else {
            throw WindowValidationError.invalid("scene","Window instances require distinct nonempty IDs")
        }
        // Prepare every resource before replacing any models. A missing texture
        // cannot leave half the scene compiled with the other half unchanged.
        var replacements: [(Entity,ModelEntity)] = []
        for (entity,component) in targets {
            let model=try await resources.makeWindow(component:component,library:library,root:resourceRoot)
            replacements.append((entity,model))
        }
        for (entity,model) in replacements {
            entity.components[ModelComponent.self]=model.model
            for child in Array(entity.children) where child.name.contains("__SharedAperture_") {child.removeFromParent()}
            for child in Array(model.children) {entity.addChild(child)}
        }
        return replacements.count
    }
}
