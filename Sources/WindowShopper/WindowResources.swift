import Foundation
import CoreGraphics
import RealityKit

/// Cache lifetime is the authored scene/session; resources are shared by URL.
@MainActor public final class WindowResources {
    private var textures: [URL: TextureResource] = [:]
    private var meshes: [String: MeshResource] = [:]
    public var meshCount: Int { meshes.count }
    public var estimatedTextureBytes: Int { textures.values.reduce(0){$0+$1.width*$1.height*4*4/3} }
    private var templates: [String: ShaderGraphMaterial] = [:]
    public private(set) var textureCount = 0
    public init() {}

    public func texture(_ name: String, root: URL) async throws -> TextureResource {
        guard WindowPreset.validResource(name) else { throw WindowValidationError.invalid(name,"Invalid resource path") }
        let base=root.resolvingSymlinksInPath().standardizedFileURL
        let url=base.appendingPathComponent(name).resolvingSymlinksInPath().standardizedFileURL
        guard url.path.hasPrefix(base.path + "/") else { throw WindowValidationError.invalid(name,"Resource escapes asset root") }
        if let existing=textures[url] { return existing }
        let loaded=try await TextureResource(contentsOf:url,options:.init(semantic:.color))
        textures[url]=loaded; textureCount=textures.count; return loaded
    }

    public func material(preset: WindowPreset, root: URL, quality: WindowQuality,
                         fogDensity: Float = 0.0185, fogBrightness: Float = 0.8,
                         fogEnabled: Bool = true) async throws -> ShaderGraphMaterial {
        try preset.validate()
        let ordered=preset.layers.map(preset.placedLayer).enumerated().sorted {
            $0.element.depth == $1.element.depth ? $0.offset < $1.offset : $0.element.depth > $1.element.depth
        }.map(\.element)
        let layers: [WindowLayer]
        switch quality {
        case .full: layers=ordered
        // Production rooms contain two foreground layers. Keeping two here
        // made the economy tier identical to full quality. Retain one near
        // silhouette plus the complete parallax shell and glass.
        case .reduced: layers=Array(ordered.suffix(1))
        case .baked:
            guard (preset.layers.isEmpty && preset.sofa == nil) || preset.bakedAppearance != nil else {
                throw WindowValidationError.invalid(preset.id,"Bake the complete layered appearance before compiling the far tier")
            }
            layers=[]
        }
        let name=quality == .baked ? "WindowShopperWindowBaked" : "WindowShopperWindow\(layers.count)"+(preset.sofa != nil ? "Sofa":"")
        if templates[name] == nil {
            guard let url=Bundle.module.url(forResource:name,withExtension:"usda") else {
                throw WindowValidationError.invalid(name,"Missing shader")
            }
            templates[name]=try await ShaderGraphMaterial(named:"/"+name,from:url)
        }
        var result=templates[name]!
        try result.setParameter(name:"SurfaceTileSize",value:.simd2Float(preset.surfaceTileSize ?? [3,3]))
        try result.setParameter(name:"SurfaceRepeat",value:.float(preset.surfaceTileSize == nil ? 0:1))
        try result.setParameter(name:"RoomSize",value:.simd2Float(preset.interiorSize))
        try result.setParameter(name:"ApertureSize",value:.simd2Float(preset.size))
        try result.setParameter(name:"ApertureOffset",value:.simd2Float(preset.apertureOffset ?? .zero))
        try result.setParameter(name:"ShutterCoverage",value:.float(preset.shutter ?? 0))
        try result.setParameter(name:"Mullion",value:.float(preset.mullion == true ? 1:0))
        try result.setParameter(name:"Crossbar",value:.float(preset.crossbar == true ? 1:0))
        try result.setParameter(name:"RoomEmissionTexture",value:.textureResource(try await texture(preset.emissionTexture ?? "WindowWhite.png",root:root)))
        try result.setParameter(name:"RoomEmissionGain",value:.float(quality == .baked ? 0: (preset.emissionGain ?? 0)))
        try result.setParameter(name:"RoomDepth",value:.float(preset.depth))
        let baked=quality == .baked ? preset.bakedAppearance : nil
        try result.setParameter(name:"ShellTexture",value:.textureResource(try await texture(baked?.texture ?? preset.shellTexture,root:root)))
        if quality != .baked {try result.setParameter(name:"SurfaceTexture",value:.textureResource(try await texture(preset.surfaceTexture ?? preset.shellTexture,root:root)))}
        if quality != .baked,let sofa=preset.fittedSofa {
            try result.setParameter(name:"SofaSize",value:.simd3Float(sofa.size))
            try result.setParameter(name:"SofaFront",value:.float(sofa.frontDepth))
            try result.setParameter(name:"SofaX",value:.float(sofa.horizontalOffset))
            try result.setParameter(name:"SofaTint",value:.color(CGColor(red:CGFloat(sofa.tint.x),green:CGFloat(sofa.tint.y),blue:CGFloat(sofa.tint.z),alpha:1)))
        }
        var shellRects=preset.shellRects
        if let baked {shellRects[0]=baked.uvRect}
        for (name,rect) in zip(["Back","Left","Right","Floor","Ceiling"],shellRects) {
            try result.setParameter(name:name+"Rect",value:.simd4Float(rect))
        }
        for (i,layer) in layers.enumerated() {
            let p="Layer\(i)"
            try result.setParameter(name:p+"Texture",value:.textureResource(try await texture(layer.texture,root:root)))
            try result.setParameter(name:p+"EmissionTexture",value:.textureResource(try await texture(layer.emissionTexture ?? "WindowWhite.png",root:root)))
            try result.setParameter(name:p+"EmissionGain",value:.float(layer.emissionGain ?? 0))
            try result.setParameter(name:p+"Depth",value:.float(layer.depth))
            try result.setParameter(name:p+"Size",value:.simd2Float(layer.size))
            try result.setParameter(name:p+"Offset",value:.simd2Float(layer.offset))
            try result.setParameter(name:p+"Opacity",value:.float(layer.opacity))
            try result.setParameter(name:p+"Tint",value:.color(CGColor(red:CGFloat(layer.tint.x),green:CGFloat(layer.tint.y),blue:CGFloat(layer.tint.z),alpha:1)))
            try result.setParameter(name:p+"Rect",value:.simd4Float(layer.uvRect))
        }
        try result.setParameter(name:"ReflectionTexture",value:.textureResource(try await texture(preset.glass.reflectionTexture,root:root)))
        try result.setParameter(name:"ReflectionRotation",value:.float((preset.glass.rotationDegrees ?? 0)/360))
        try result.setParameter(name:"ReflectionExposure",value:.float(preset.glass.exposure ?? 1))
        try result.setParameter(name:"ReflectionBlur",value:.float(preset.glass.roughness ?? 0))
        try result.setParameter(name:"ReflectionOnly",value:.float(0))
        try result.setParameter(name:"ReflectionStrength",value:.float(preset.glass.reflectionStrength))
        try result.setParameter(name:"GlassTint",value:.color(CGColor(red:CGFloat(preset.glass.tint.x),green:CGFloat(preset.glass.tint.y),blue:CGFloat(preset.glass.tint.z),alpha:1)))
        for (name,value) in [("DistrictAmbientGain",preset.ambientGain),("DistrictHighlightGain",preset.highlightGain),
                              ("FogDensity",-fogDensity),("FogBrightness",fogBrightness),("FogEnabled",fogEnabled ? Float(1):0)] {
            try result.setParameter(name:name,value:.float(value))
        }
        // Occlusion is already baked in the room atlas; use a shared white map.
        let white=try await texture("WindowWhite.png",root:root)
        try result.setParameter(name:"OcclusionMap",value:.textureResource(white))
        result.faceCulling = .back
        return result
    }

    public func mesh(preset:WindowPreset) throws -> MeshResource {
        let offset=preset.apertureOffset ?? .zero
        let values=[preset.size.x,preset.size.y,preset.interiorSize.x,preset.interiorSize.y,offset.x,offset.y]
        let key=(preset.shape ?? .rectangle).rawValue+values.map{String($0.bitPattern)}.joined(separator:",")
        if let cached=meshes[key] {return cached}
        let value=try WindowGeometry.surface(size:preset.size,shape:preset.shape ?? .rectangle,roomSize:preset.interiorSize,offset:offset)
        meshes[key]=value;return value
    }
    public func makeWindow(component: WindowComponent, library: WindowLibrary, root: URL) async throws -> ModelEntity {
        let preset=try component.resolved(in:library)
        if let apertures=preset.apertures {
            let group=ModelEntity();group.name=component.id;group.components.set(component)
            for (i,a) in apertures.enumerated() {
                var p=preset;p.apertures=nil;p.size=a.size;p.apertureOffset=a.offset
                p.shutter=a.shutter;p.mullion=a.mullion;p.crossbar=a.crossbar
                let child=try await makeWindow(component:.init(id:component.id+"__SharedAperture_\(i)",presetID:p.id,override:p,quality:component.quality),library:library,root:root)
                child.position=[a.offset.x,a.offset.y,0];group.addChild(child)
            }
            return group
        }
        let m=try await material(preset:preset,root:root,quality:component.quality)
        let mesh=try mesh(preset:preset)
        let entity=ModelEntity(mesh:mesh,materials:[m])
        entity.name=component.id;entity.components.set(component);return entity
    }
}
