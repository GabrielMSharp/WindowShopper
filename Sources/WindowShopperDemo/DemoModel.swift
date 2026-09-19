import SwiftUI
import RealityKit
import WindowShopper
import ImageIO
import UniformTypeIdentifiers

@MainActor @Observable final class DemoModel {
    var preset: WindowPreset
    var quality: WindowQuality = .full
    var fog = false
    var fogDensity: Float = 0.0185
    var fogBrightness: Float = 0.55
    var headlights = false
    var reflectionsOnly = false
    var frames = true
    var yaw: Float = 0
    var pitch: Float = 0
    var distance: Float = 5
    var eyeOffset: Float = 0
    var sweep = false
    var statistics = false
    var busy = false
    var error: String?
    var status = "Preparing window…"
    var lastBuildMilliseconds: Double = 0
    var textureCount = 0
    var selectedPreset = "diagnostic"
    var revision = 0
    var library: [WindowPreset] = []
    @ObservationIgnored let stage = Entity()
    @ObservationIgnored let camera = PerspectiveCamera()
    @ObservationIgnored private var resources = WindowResources()
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var startupError:String?
    @ObservationIgnored private var baseline: WindowPreset
    @ObservationIgnored let assetRoot: URL

    init() {
        assetRoot=FileManager.default.temporaryDirectory.appendingPathComponent("WindowShopper-"+UUID().uuidString,isDirectory:true)
        let fallback=WindowPreset(id:"diagnostic",displayName:"Depth calibration",size:[3.2,2.6],depth:2.5,
            shellTexture:"CalibrationShell.png",shellRects:(0..<5).map{[Float($0)/5+0.002,0.01,Float($0+1)/5-0.002,0.99]},
            layers:[.init(id:"Curtains",texture:"CalibrationCurtains.png",depth:0.12,size:[3.2,2.6],anchor:.fitWindow)],
            glass:.init(reflectionTexture:"WindowNightReflection.png",reflectionStrength:0.3,exposure:3,roughness:0.08),sofa:.init(),ambientGain:1,highlightGain:1)
        preset=fallback;baseline=fallback;library=[fallback]
        do {
            try FileManager.default.createDirectory(at:assetRoot,withIntermediateDirectories:true)
            let starters=try WindowLibrary.starter().presets
            var names:Set<String>=["WindowWhite.png","WindowNightReflection.png"]
            for p in starters {
                names.formUnion(p.resourceNames)
            }
            for name in names {
                let destination=assetRoot.appendingPathComponent(name)
                try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
                try FileManager.default.copyItem(at:WindowLibrary.starterResourceRoot.appendingPathComponent(name),to:destination)
            }
            try CalibrationTextures.write(to:assetRoot)
            library=[fallback]+starters
        } catch {self.startupError=String(describing:error);self.error=startupError}
        camera.camera.fieldOfViewInDegrees=50
        WindowComponent.registerComponent()
        let arguments=ProcessInfo.processInfo.arguments
        if let option=arguments.firstIndex(of:"--preset"),arguments.indices.contains(option+1) {
            choose(arguments[option+1])
        }
    }
    var buildKey: String {
        let data=(try? JSONEncoder().encode(preset)) ?? Data()
        return data.base64EncodedString()+"\(quality.rawValue)-\(fog)-\(fogDensity)-\(fogBrightness)-\(headlights)-\(reflectionsOnly)-\(frames)-\(revision)"
    }
    func choose(_ id:String) {
        guard var p=library.first(where:{$0.id==id}) else {error="Unknown preset: \(id)";return}
        WindowPresetCatalog.fitNightArtwork(&p)
        selectedPreset=id;preset=p;baseline=p
    }
    func reset() {preset=baseline;quality = .full;error=nil}
    func addLayer() {
        guard preset.layers.count < 4 else {return}
        preset.layers.append(.init(id:"Layer_"+String(UUID().uuidString.prefix(6)),texture:"CalibrationFurniture.png",depth:min(preset.depth*0.5,1),size:[1,1],uvRect:[0,55.0/512,1,1],anchor:.floor))
    }
    func moveLayer(_ index:Int,_ delta:Int) {
        let next=index+delta
        guard preset.layers.indices.contains(next) else {return}
        preset.layers.swapAt(index,next)
    }
    func rebuild() async {
        generation += 1;let ticket=generation
        let snapshot=preset,q=quality,showFrame=frames,useFog=fog,density=fogDensity,brightness=fogBrightness,light=headlights,reflectionView=reflectionsOnly
        busy=true
        do {
            try await Task.sleep(for:.milliseconds(100))
            try Task.checkCancellation()
            let start=ContinuousClock.now
            let entity=try await resources.makeWindow(component:.init(id:"LabWindow",presetID:snapshot.id,override:snapshot,quality:q),library:.init(presets:[snapshot]),root:assetRoot)
            func models(_ e:Entity)->[Entity] {[e]+e.children.flatMap(models)}
            for part in models(entity) {
                guard var model=part.components[ModelComponent.self] else {continue}
                model.materials=model.materials.map { original in
                    guard var material=original as? ShaderGraphMaterial else {return original}
                    try? material.setParameter(name:"ReflectionOnly",value:.float(reflectionView ? 1:0))
                    try? material.setParameter(name:"FogDensity",value:.float(-density))
                    try? material.setParameter(name:"FogBrightness",value:.float(brightness))
                    try? material.setParameter(name:"FogEnabled",value:.float(useFog ? 1:0))
                    try? material.setParameter(name:"HeadlightOrigin",value:.simd3Float([0,0,3]))
                    try? material.setParameter(name:"HeadlightForward",value:.simd3Float([0,0,-1]))
                    try? material.setParameter(name:"HeadlightEnabled",value:.float(light ? 1:0))
                    return material
                }
                part.components.set(model)
            }
            try Task.checkCancellation()
            guard ticket==generation else {return}
            stage.children.removeAll();stage.addChild(entity)
            if showFrame {try addFrame(preset:snapshot)}
            lastBuildMilliseconds=Double(start.duration(to:.now).components.attoseconds)/1e15+Double(start.duration(to:.now).components.seconds)*1000
            textureCount=resources.textureCount
            status="\(q.rawValue.capitalized) · \(snapshot.layers.count) layers · opaque surface"
            error=startupError;busy=false
        } catch is CancellationError {
            if ticket==generation {busy=false}
        } catch {
            guard ticket==generation else {return}
            self.error=String(describing:error);status="Preview retains the last valid window";busy=false
        }
    }
    private func addFrame(preset:WindowPreset) throws {
        var material=UnlitMaterial(color:.init(white:0.2,alpha:1));material.faceCulling = .none
        let openings=preset.apertures ?? [.init(size:preset.size)]
        for a in openings {
            let frame=ModelEntity(mesh:try WindowGeometry.frame(size:a.size,shape:preset.shape ?? .rectangle),materials:[material])
            frame.position=[a.offset.x,a.offset.y,0];frame.name="PhysicalFrame";stage.addChild(frame)
        }
    }
    func setApertureCount(_ count:Int) {
        let count=max(1,min(4,count)), pitch=preset.size.x+0.3
        preset.roomSize=[Float(count)*pitch-0.3,preset.size.y]
        preset.apertureOffset=nil
        preset.apertures=count==1 ? nil : (0..<count).map {i in
            .init(size:preset.size,offset:[(Float(i)-Float(count-1)/2)*pitch,0],shutter:i==0 ? 0.3:0,mullion:i==count-1)
        }
        refitBundledArtwork()
    }
    func resizeRoom(width:Float? = nil,height:Float? = nil) {
        preset.roomSize=[width ?? preset.interiorSize.x,height ?? preset.interiorSize.y]
        refitBundledArtwork()
    }
    private func refitBundledArtwork() {
        // Custom portable artwork must survive dimension/aperture edits.
        guard ["WindowNightRooms.png","WindowNightWide.png"].contains(preset.shellTexture),
              ["WindowNightEmission.png","WindowNightWideEmission.png"].contains(preset.emissionTexture ?? "") else {return}
        if let source=library.first(where:{$0.id==selectedPreset}) {
            preset.shellTexture=source.shellTexture;preset.shellRects=source.shellRects;preset.emissionTexture=source.emissionTexture
            WindowPresetCatalog.fitNightArtwork(&preset)
        }
    }
    func resize(width:Float? = nil,height:Float? = nil) {
        if let width {preset.size.x=width}
        if let height {preset.size.y=height}
        if preset.roomSize != nil {setApertureCount(preset.apertures?.count ?? 1)}
        for i in preset.layers.indices where preset.layers[i].anchor == .fitWindow {
            preset.layers[i].size=preset.size;preset.layers[i].offset = .zero
        }
    }
    func updateCamera() {
        let a=yaw * .pi/180,b=pitch * .pi/180
        let position=SIMD3<Float>(sin(a)*cos(b)*distance+eyeOffset,sin(b)*distance,cos(a)*cos(b)*distance)
        camera.look(at:.zero,from:position,relativeTo:nil)
    }
    func importImage(_ url:URL,for target:ImageTarget) throws {
        let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
        let name=UUID().uuidString+"."+url.pathExtension
        let destination=assetRoot.appendingPathComponent(name)
        try FileManager.default.copyItem(at:url,to:destination)
        switch target {
        case .shell:preset.shellTexture=name
        case .reflection:preset.glass.reflectionTexture=name
        case .surfaces:preset.surfaceTexture=name
        case .emission:preset.emissionTexture=name;preset.emissionGain=max(1,preset.emissionGain ?? 0)
        case .baked:preset.bakedAppearance = .init(texture:name)
        case .layer(let id):
            if let i=preset.layers.firstIndex(where:{$0.id==id}) {preset.layers[i].texture=name;preset.layers[i].uvRect=[0,0,1,1]}
        }
        resources=WindowResources();revision += 1
    }
    func document() throws -> DemoDocument {
        try preset.validate()
        let names=preset.resourceNames
        var images:[String:Data]=[:]
        for name in names {
            guard WindowPreset.validResource(name) else {throw WindowValidationError.invalid(name,"Invalid resource")}
            images[name]=try Data(contentsOf:assetRoot.appendingPathComponent(name))
        }
        return DemoDocument(payload:.init(version:1,preset:preset,images:images))
    }
    func load(_ url:URL) throws {
        let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
        let data=try Data(contentsOf:url)
        let payload=try JSONDecoder().decode(DemoDocument.Payload.self,from:data)
        try payload.validate()
        for (name,bytes) in payload.images {
            let path=assetRoot.appendingPathComponent(name)
            try FileManager.default.createDirectory(at:path.deletingLastPathComponent(),withIntermediateDirectories:true)
            try bytes.write(to:path,options:.atomic)
        }
        resources=WindowResources();preset=payload.preset;baseline=preset;selectedPreset="custom";quality = .full;revision += 1
    }
}

enum ImageTarget: Equatable {case shell,surfaces,emission,reflection,baked,layer(String)}
struct DemoDocument: FileDocument {
    static var readableContentTypes:[UTType] {[.json]}
    struct Payload: Codable {
        var version:Int
        var preset:WindowPreset
        var images:[String:Data]
        func validate() throws {
            guard version==1 else {throw WindowValidationError.invalid("document","Unsupported version")}
            try preset.validate()
            guard images.keys.allSatisfy(WindowPreset.validResource) else {throw WindowValidationError.invalid("document","Invalid resource path")}
            let required=preset.resourceNames
            guard required.allSatisfy({images[$0] != nil}) else {throw WindowValidationError.invalid("document","Missing embedded texture")}
        }
    }
    var payload:Payload
    init(payload:Payload) {self.payload=payload}
    init(configuration:ReadConfiguration) throws {
        guard let data=configuration.file.regularFileContents else {throw CocoaError(.fileReadCorruptFile)}
        payload=try JSONDecoder().decode(Payload.self,from:data);try payload.validate()
    }
    func fileWrapper(configuration:WriteConfiguration) throws -> FileWrapper {
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        return FileWrapper(regularFileWithContents:try encoder.encode(payload))
    }
}
