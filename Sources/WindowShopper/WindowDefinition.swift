import Foundation
import RealityKit

/// Metres, Y up, front normal +Z; positive depth recedes along -Z.
/// Image UVs use a bottom-left origin. RGBA layer images use straight alpha.
public enum WindowLayerAnchor: String, Codable, CaseIterable, Sendable { case free, floor, ceiling, fitWindow }
public enum WindowShape: String, Codable, CaseIterable, Sendable { case rectangle, rounded, chamfered, arch, oval, capsule }

/// Optional analytic solid used for close-view sofa calibration.
public struct WindowSofa: Codable, Equatable, Sendable {
    public var size: SIMD3<Float>
    public var frontDepth: Float
    public var horizontalOffset: Float
    public var tint: SIMD3<Float>
    public init(size: SIMD3<Float> = [1.6,0.9,0.75], frontDepth: Float = 0.8,
                horizontalOffset: Float = 0, tint: SIMD3<Float> = [0.65,0.3,0.09]) {
        self.size=size;self.frontDepth=frontDepth;self.horizontalOffset=horizontalOffset;self.tint=tint
    }
}

public struct WindowLayer: Codable, Equatable, Sendable {
    public var id: String
    public var texture: String
    public var depth: Float
    public var size: SIMD2<Float>
    public var offset: SIMD2<Float>
    public var opacity: Float
    public var tint: SIMD3<Float>
    public var uvRect: SIMD4<Float>
    public var anchor: WindowLayerAnchor?
    public var emissionTexture: String?
    public var emissionGain: Float?
    public init(id: String, texture: String, depth: Float, size: SIMD2<Float>,
                offset: SIMD2<Float> = .zero, opacity: Float = 1,
                tint: SIMD3<Float> = .one, uvRect: SIMD4<Float> = [0,0,1,1], anchor: WindowLayerAnchor? = nil) {
        self.id=id; self.texture=texture; self.depth=depth; self.size=size
        self.offset=offset; self.opacity=opacity; self.tint=tint; self.uvRect=uvRect;self.anchor=anchor
    }
}

public struct WindowGlass: Codable, Equatable, Sendable {
    public var reflectionTexture: String
    public var reflectionStrength: Float
    public var rotationDegrees: Float?
    public var exposure: Float?
    public var roughness: Float?
    public var tint: SIMD3<Float>
    /// Equirectangular, world-oriented baked environment. No capture per window.
    public init(reflectionTexture: String, reflectionStrength: Float = 0.06,
                tint: SIMD3<Float> = .one, rotationDegrees: Float? = nil, exposure: Float? = nil, roughness: Float? = nil) {
        self.rotationDegrees=rotationDegrees;self.exposure=exposure;self.roughness=roughness
        self.reflectionTexture=reflectionTexture; self.reflectionStrength=reflectionStrength; self.tint=tint
    }
}

public struct WindowBakedAppearance: Codable, Equatable, Sendable {
    public var texture: String
    public var uvRect: SIMD4<Float>
    public init(texture: String, uvRect: SIMD4<Float> = [0,0,1,1]) {
        self.texture=texture; self.uvRect=uvRect
    }
}

/// One physical opening into a shared room, expressed in the room's XY frame.
public struct WindowAperture: Codable, Equatable, Sendable {
    public var size: SIMD2<Float>
    public var offset: SIMD2<Float>
    public var shutter: Float
    public var mullion: Bool
    public var crossbar: Bool
    public init(size: SIMD2<Float>, offset: SIMD2<Float> = .zero,
                shutter: Float = 0, mullion: Bool = false, crossbar: Bool = false) {
        self.size=size;self.offset=offset;self.shutter=shutter;self.mullion=mullion;self.crossbar=crossbar
    }
}

public struct WindowPreset: Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var size: SIMD2<Float>
    public var depth: Float
    public var shellTexture: String
    /// Optional fields keep previously saved presets readable.
    public var roomSize: SIMD2<Float>?
    public var apertureOffset: SIMD2<Float>?
    public var apertures: [WindowAperture]?
    public var shutter: Float?
    public var mullion: Bool?
    public var crossbar: Bool?
    public var emissionTexture: String?
    public var emissionGain: Float?
    public var interiorSize: SIMD2<Float> { roomSize ?? size }
    public var resourceNames: Set<String> {
        Set([shellTexture, glass.reflectionTexture, "WindowWhite.png"] + layers.map(\.texture)
            + [surfaceTexture, emissionTexture, bakedAppearance?.texture].compactMap { $0 }
            + layers.compactMap(\.emissionTexture))
    }
    public var bakedAppearance: WindowBakedAppearance?
    public var shape: WindowShape?
    public var surfaceTileSize: SIMD2<Float>?
    public var surfaceTexture: String?
    public var sofa: WindowSofa?
    /// back, left, right, floor, ceiling. Back uses shellTexture; other faces
    /// use surfaceTexture when supplied, otherwise shellTexture.
    public var shellRects: [SIMD4<Float>]
    public var layers: [WindowLayer]
    public var glass: WindowGlass
    public var ambientGain: Float
    public var highlightGain: Float
    public init(id: String, displayName: String, size: SIMD2<Float>, depth: Float,
                shellTexture: String, shellRects: [SIMD4<Float>], layers: [WindowLayer] = [],
                glass: WindowGlass, bakedAppearance: WindowBakedAppearance? = nil, shape: WindowShape? = nil, surfaceTexture: String? = nil, sofa: WindowSofa? = nil, ambientGain: Float = 0.42, highlightGain: Float = 0.72) {
        self.id=id; self.displayName=displayName; self.size=size; self.depth=depth
        self.shellTexture=shellTexture; self.shellRects=shellRects; self.layers=layers
        self.bakedAppearance=bakedAppearance;self.shape=shape;self.surfaceTexture=surfaceTexture;self.sofa=sofa
        self.glass=glass; self.ambientGain=ambientGain; self.highlightGain=highlightGain
    }
    public func validate() throws {
        func require(_ value: Bool, _ reason: String) throws {
            if !value { throw WindowValidationError.invalid(id, reason) }
        }
        try require(!id.isEmpty && !displayName.isEmpty, "Missing identity")
        try require(size.x.isFinite && size.y.isFinite && size.x > 0 && size.y > 0 && depth.isFinite && depth > 0, "Invalid room dimensions")
        try require(shellRects.count == 5 && shellRects.allSatisfy(Self.validRect), "Five valid shell rectangles required")
        let room=interiorSize, offset=apertureOffset ?? .zero
        try require(room.x.isFinite && room.y.isFinite && room.x>0 && room.y>0, "Invalid shared room size")
        try require(offset.x.isFinite && offset.y.isFinite && abs(offset.x)+size.x/2<=room.x/2+0.001 && abs(offset.y)+size.y/2<=room.y/2+0.001, "Aperture outside room")
        try require(Self.unit(shutter ?? 0), "Invalid shutter coverage")
        try require(emissionTexture.map(Self.validResource) ?? true, "Invalid emission resource")
        try require((emissionGain ?? 0).isFinite && (0...8).contains(emissionGain ?? 0), "Invalid emission gain")
        if let apertures {
            try require(!apertures.isEmpty && apertures.count<=4, "One to four shared apertures required")
            for a in apertures {
                try require(a.size.x.isFinite && a.size.y.isFinite && a.size.x>0 && a.size.y>0 && a.offset.x.isFinite && a.offset.y.isFinite && abs(a.offset.x)+a.size.x/2<=room.x/2+0.001 && abs(a.offset.y)+a.size.y/2<=room.y/2+0.001 && Self.unit(a.shutter), "Invalid shared aperture")
            }
        }
        try require(layers.count <= 4, "At most four layers")
        try require(Set(layers.map(\.id)).count == layers.count, "Duplicate layer identity")
        try require(Self.validResource(shellTexture) && Self.validResource(glass.reflectionTexture), "Invalid resource path")
        try require(Self.unit(glass.reflectionStrength) && Self.validTint(glass.tint), "Invalid glass")
        try require(Self.unit(ambientGain) && Self.unit(highlightGain), "Lighting gains must be within 0...1")
        if let tile=surfaceTileSize {try require(tile.x.isFinite && tile.y.isFinite && tile.x>0 && tile.y>0,"Invalid surface tile size")}
        try require(surfaceTexture.map(Self.validResource) ?? true, "Invalid side-surface resource")
        try require((glass.rotationDegrees ?? 0).isFinite && (glass.exposure ?? 1).isFinite && (0...8).contains(glass.exposure ?? 1) && Self.unit(glass.roughness ?? 0), "Invalid reflection controls")
        if let sofa {
            try require((0..<3).allSatisfy {sofa.size[$0].isFinite && sofa.size[$0] > 0} && sofa.frontDepth.isFinite && sofa.frontDepth >= 0 && sofa.horizontalOffset.isFinite && Self.validTint(sofa.tint), "Invalid solid sofa")
        }
        if let bakedAppearance {
            try require(Self.validResource(bakedAppearance.texture) && Self.validRect(bakedAppearance.uvRect), "Invalid baked appearance")
        }
        for layer in layers {
            try require(layer.emissionTexture.map(Self.validResource) ?? true, "Invalid layer emission")
            try require((layer.emissionGain ?? 0).isFinite && (0...8).contains(layer.emissionGain ?? 0), "Invalid layer emission gain")
            try require(!layer.id.isEmpty && Self.validResource(layer.texture), "Invalid layer identity or resource")
            try require(layer.depth.isFinite && layer.depth >= 0 && layer.depth < depth, "Layer must sit before back wall")
            try require(layer.size.x.isFinite && layer.size.y.isFinite && layer.size.x > 0 && layer.size.y > 0, "Invalid layer size")
            try require(layer.offset.x.isFinite && layer.offset.y.isFinite && Self.unit(layer.opacity) && Self.validTint(layer.tint) && Self.validRect(layer.uvRect), "Invalid layer appearance")
        }
    }
    static func unit(_ n: Float) -> Bool { n.isFinite && (0...1).contains(n) }
    static func validTint(_ n: SIMD3<Float>) -> Bool { (0..<3).allSatisfy { unit(n[$0]) } }
    static func validRect(_ r: SIMD4<Float>) -> Bool {
        (0..<4).allSatisfy { unit(r[$0]) } && r.z > r.x && r.w > r.y
    }
    public static func validResource(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains(":") && !path.contains("\\")
            && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != ".." && $0 != "." }
    }
}

public enum WindowValidationError: Error, CustomStringConvertible {
    case invalid(String, String)
    public var description: String { switch self { case let .invalid(id, reason): "Window \(id): \(reason)" } }
}

public enum WindowQuality: String, Codable, Sendable { case full, reduced, baked }

/// Overrides are an independent preset value, never a mutation of the library.
public struct WindowComponent: Component, Codable, Equatable {
    public var id: String
    public var presetID: String
    public var override: WindowPreset?
    public var variationSeed: UInt32
    public var quality: WindowQuality
    public init(id: String, presetID: String, override: WindowPreset? = nil,
                variationSeed: UInt32 = 0, quality: WindowQuality = .full) {
        self.id=id; self.presetID=presetID; self.override=override
        self.variationSeed=variationSeed; self.quality=quality
    }
    public func resolved(in library: WindowLibrary) throws -> WindowPreset {
        guard let base=library.presets.first(where: { $0.id == presetID }) else {
            throw WindowValidationError.invalid(id, "Unknown preset \(presetID)")
        }
        let value=override ?? base; try value.validate(); return value
    }
}

public struct WindowLibrary: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var presets: [WindowPreset]
    public init(presets: [WindowPreset]) { self.presets=presets }
    public func validate() throws {
        guard schemaVersion == 1, Set(presets.map(\.id)).count == presets.count else {
            throw WindowValidationError.invalid("library", "Unsupported version or duplicate presets")
        }
        for preset in presets { try preset.validate() }
    }
}

public extension WindowPreset {
    /// Anchors use image bounds: crop transparent padding at the feet first.
    func placedLayer(_ layer: WindowLayer) -> WindowLayer {
        var value=layer
        switch layer.anchor ?? .free {
        case .free: break
        case .floor: value.offset.y = -interiorSize.y/2 + layer.size.y/2 + layer.offset.y
        case .ceiling: value.offset.y = interiorSize.y/2 - layer.size.y/2 + layer.offset.y
        case .fitWindow: value.size=size;value.offset = apertureOffset ?? .zero
        }
        return value
    }
    var fittedSofa: WindowSofa? {
        guard var sofa else {return nil}
        sofa.size=[min(sofa.size.x,interiorSize.x*0.88),min(sofa.size.y,interiorSize.y*0.75),min(sofa.size.z,depth*0.75)]
        let backClearance=min(0.01,depth*0.025)
        sofa.frontDepth=min(sofa.frontDepth,max(0,depth-sofa.size.z-backClearance))
        let limit=max(0,(interiorSize.x-sofa.size.x)/2-0.02)
        sofa.horizontalOffset=min(limit,max(-limit,sofa.horizontalOffset))
        return sofa
    }
}
