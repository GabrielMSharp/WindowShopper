import Foundation
import CryptoKit

/// Shared by the game, offline bake compiler and native integration audit.
public enum WindowPresetCatalog {
    public static let residential=["apartment_evening","apartment_privacy","listening_afterhours","reading_room","laundry_room"]
    public static let service=["cafe_tables","cafe_closed","avionics_workshift","avionics_standby","transit_night","clinic_night","noodle_bar","freight_office","server_room","hydroponic_dusk"]
    public static var ids:[String] { residential+service }
    public static let bakeSize:SIMD2<Float>=[3.2,2.86]
    public static func seed(_ text:String) -> UInt32 {
        text.utf8.reduce(UInt32(2166136261)) {($0 ^ UInt32($1)) &* 16777619}
    }
    public static func presetID(host:String,ordinal:Int,residential isResidential:Bool)->String {
        let choices=isResidential ? residential:service
        return choices[(Int(seed(host))+ordinal)%choices.count]
    }
    /// Refit an exterior illusion to an existing physical aperture. Preserve its
    /// actual frame; never resize the city or project a new room over an open terrace.
    public static func fitted(_ original:WindowPreset,size:SIMD2<Float>) -> WindowPreset {
        var p=original
        let ratio=size/original.size
        p.size=size;p.shape = .rectangle
        for i in p.layers.indices {
            if p.layers[i].anchor == .fitWindow {p.layers[i].size=size;continue}
            p.layers[i].size *= min(1,min(ratio.x,ratio.y))
            p.layers[i].offset.x *= ratio.x
            let limit=max(0,(size.x-p.layers[i].size.x)/2-0.02)
            p.layers[i].offset.x=max(-limit,min(limit,p.layers[i].offset.x))
        }
        if var sofa=p.sofa {sofa.horizontalOffset *= ratio.x;p.sofa=sofa}
        return p
    }
    /// The production artwork is authored at night; never apply a second exposure grade.
    public static func nightAppearance(_ original:WindowPreset) -> WindowPreset { original }
    /// Use dedicated wide compositions for connected rooms, maintaining image aspect.
    public static func fitNightArtwork(_ p:inout WindowPreset) {
        guard p.shellTexture == "WindowNightRooms.png" else {return}
        let aspect=p.interiorSize.x/p.interiorSize.y
        if aspect>1.55 {
            let tile=p.id.contains("apartment") || p.id.contains("reading") || p.id.contains("listening") ? 0 : (p.id.contains("avionics") || p.id.contains("server") ? 2:1)
            p.shellTexture="WindowNightWide.png";p.emissionTexture="WindowNightWideEmission.png"
            p.shellRects[0]=[0.004,Float(2-tile)/3+0.004,0.996,Float(3-tile)/3-0.004]
            let span=min(1,aspect/4.5),mid:Float=0.5
            p.shellRects[0].x=mid-span*0.492;p.shellRects[0].z=mid+span*0.492
        } else {
            let width=p.shellRects[0].z-p.shellRects[0].x,mid=(p.shellRects[0].z+p.shellRects[0].x)/2
            let span=min(1,aspect/1.5)
            p.shellRects[0].x=mid-width*span/2;p.shellRects[0].z=mid+width*span/2
        }
    }
    public struct Bakes:Codable {
        public var sourceLibrarySHA256:String
        public var texture:String
        public var rects:[String:SIMD4<Float>]
        public init(sourceLibrarySHA256:String,texture:String,rects:[String:SIMD4<Float>]) {
            self.sourceLibrarySHA256=sourceLibrarySHA256;self.texture=texture;self.rects=rects
        }
    }
    public static func libraryDigest() throws -> String {
        let data=try Data(contentsOf:WindowLibrary.starterResourceRoot.appendingPathComponent("WindowPresets.json"))
        return SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
    }
    public static func bakes() throws -> Bakes {
        let data=try Data(contentsOf:WindowLibrary.starterResourceRoot.appendingPathComponent("CityWindowBakes.json"))
        let bakes=try JSONDecoder().decode(Bakes.self,from:data)
        guard bakes.sourceLibrarySHA256 == (try libraryDigest()),ids.allSatisfy({bakes.rects[$0] != nil}),WindowPreset.validResource(bakes.texture) else {
            throw WindowValidationError.invalid("city bakes","Regenerate the distant atlas after editing the library")
        }
        return bakes
    }
}
