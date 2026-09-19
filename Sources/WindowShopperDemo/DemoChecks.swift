import Foundation
import RealityKit
import Metal
import ImageIO
import UniformTypeIdentifiers
import WindowShopper

/// Run the real model and renderer without depending on accessibility automation.
@MainActor enum DemoChecks {
    static func captureGIF(at output:URL) async throws {
        let lab=DemoModel()
        lab.choose("night_cafe")
        lab.frames=true
        await lab.rebuild()
        if let error=lab.error {throw WindowValidationError.invalid("GIF",error)}

        let renderer=try RealityRenderer()
        guard let device=MTLCreateSystemDefaultDevice() else {
            throw WindowValidationError.invalid("GIF","No Metal device")
        }
        renderer.cameraSettings.colorBackground = .color(CGColor(red:0.025,green:0.035,blue:0.055,alpha:1))
        renderer.cameraSettings.isToneMappingEnabled=false
        let root=Entity(),camera=PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees=48
        root.addChild(lab.stage);root.addChild(camera)
        renderer.activeCamera=camera;renderer.entities.append(root)

        let width=640,height=480
        let descriptor=MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat:.rgba8Unorm_srgb,width:width,height:height,mipmapped:false)
        descriptor.storageMode = .shared;descriptor.usage=[.renderTarget,.shaderRead]
        guard let target=device.makeTexture(descriptor:descriptor) else {
            throw WindowValidationError.invalid("GIF","Cannot create render target")
        }
        let cameraOutput=try RealityRenderer.CameraOutput(.singleProjection(colorTexture:target))
        try FileManager.default.createDirectory(at:output.deletingLastPathComponent(),withIntermediateDirectories:true)
        guard let destination=CGImageDestinationCreateWithURL(
            output as CFURL,UTType.gif.identifier as CFString,48,
            [kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary) else {
            throw WindowValidationError.invalid("GIF","Cannot create destination")
        }
        for frame in 0..<48 {
            let phase=Float(frame)/48*2*Float.pi
            let yaw=sin(phase)*0.78
            let position=SIMD3<Float>(sin(yaw)*5.8,0.45+sin(phase*2)*0.18,cos(yaw)*5.8)
            camera.look(at:.zero,from:position,relativeTo:nil)
            for _ in 0..<2 {
                try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
                    do {try renderer.updateAndRender(deltaTime:1/24,cameraOutput:cameraOutput,onComplete:{_ in continuation.resume()})}
                    catch {continuation.resume(throwing:error)}
                }
            }
            var bytes=[UInt8](repeating:0,count:width*height*4)
            bytes.withUnsafeMutableBytes {
                target.getBytes($0.baseAddress!,bytesPerRow:width*4,
                    from:MTLRegionMake2D(0,0,width,height),mipmapLevel:0)
            }
            guard let provider=CGDataProvider(data:Data(bytes) as CFData),
                  let image=CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,
                    bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,
                    decode:nil,shouldInterpolate:true,intent:.defaultIntent) else {
                throw WindowValidationError.invalid("GIF","Cannot create frame")
            }
            CGImageDestinationAddImage(destination,image,
                [kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:1.0/24.0]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {
            throw WindowValidationError.invalid("GIF","Cannot finalize animation")
        }
        print("WINDOW_SHOPPER_GIF_WRITTEN \(output.path)")
    }

    static func run() async throws {
        let output=URL(fileURLWithPath:ProcessInfo.processInfo.environment["WINDOW_SHOPPER_EVIDENCE"] ?? "/tmp/DemoChecks",isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        func check(_ value:Bool,_ message:String) throws {
            if !value {throw WindowValidationError.invalid("DemoChecks",message)}
        }
        let lab=DemoModel()
        try check(lab.library.count >= 20,"Preset initialization: \(lab.error ?? "no error")")
        await lab.rebuild()
        try check(lab.error == nil,"Initial preview: \(lab.error ?? "")")
        let original=lab.preset
        lab.preset.layers[0].depth=0.67
        lab.preset.layers[0].tint=[0.7,0.8,0.9]
        lab.preset.glass.reflectionStrength=0.19
        await lab.rebuild()
        try check(lab.error == nil,"Live property update failed")
        let saved=lab.preset
        let document=try lab.document()
        let file=output.appendingPathComponent("RoundTrip.windowlab.json")
        try JSONEncoder().encode(document.payload).write(to:file,options:.atomic)
        let reopened=DemoModel()
        try reopened.load(file)
        await reopened.rebuild()
        try check(reopened.error == nil,"Reloaded resources failed")
        try check(reopened.preset == saved,"Preset did not survive save/reopen")
        let reopenedDocument=try reopened.document()
        try check(reopenedDocument.payload.images == document.payload.images,"Embedded images changed")
        let retained=reopened.stage.findEntity(named:"LabWindow")
        reopened.preset.depth=0
        await reopened.rebuild()
        try check(reopened.error != nil && reopened.stage.findEntity(named:"LabWindow") === retained,"Invalid input must preserve the last valid entity")
        reopened.reset();await reopened.rebuild()
        try check(reopened.preset == saved && reopened.error == nil,"Reset did not restore loaded baseline")
        reopened.quality = .baked;await reopened.rebuild()
        try check(reopened.error != nil,"Missing far bake must report an error")
        reopened.quality = .full
        reopened.preset=original
        while reopened.preset.layers.count<4 {reopened.addLayer()}
        reopened.addLayer()
        try check(reopened.preset.layers.count==4,"Four-layer limit failed")
        await reopened.rebuild()
        try check(reopened.error == nil,"Four-layer preview failed")
        reopened.preset=original;await reopened.rebuild()

        reopened.choose("apartment_evening")
        let dressedDocument=try reopened.document()
        try check(dressedDocument.payload.images["WindowNightProps.png"] != nil && dressedDocument.payload.images[reopened.preset.emissionTexture ?? ""] != nil,"Dressed preset must embed both RGBA atlases")
        let dressedURL=output.appendingPathComponent("DressedRoom.windowlab.json")
        try JSONEncoder().encode(dressedDocument.payload).write(to:dressedURL,options:.atomic)
        try reopened.load(dressedURL)
        await reopened.rebuild()
        try check(reopened.error == nil && reopened.preset == dressedDocument.payload.preset,"Dressed room persistence failed")
        try check(try reopened.document().payload.images == dressedDocument.payload.images,"Dressed texture bytes changed")
        reopened.choose("connected_office")
        let connected=try reopened.document()
        try check(connected.payload.preset.apertures?.count==3,"Shared room has no apertures")
        let connectedURL=output.appendingPathComponent("ConnectedOffice.windowlab.json")
        try JSONEncoder().encode(connected.payload).write(to:connectedURL,options:.atomic)
        try reopened.load(connectedURL);await reopened.rebuild()
        try check(reopened.error==nil && reopened.preset==connected.payload.preset,"Connected-room persistence failed")
        try check(reopened.stage.findEntity(named:"LabWindow")?.children.count==3,"Shared preview does not contain three openings")
        try check(try reopened.document().payload.images==connected.payload.images,"Shared-room emission bytes changed")
        reopened.preset=original;await reopened.rebuild()
        // Exercise the same file import path as the Replace Image control.
        try reopened.importImage(reopened.assetRoot.appendingPathComponent("CalibrationCurtains.png"),for:.layer(original.layers[0].id))
        await reopened.rebuild()
        try check(reopened.error == nil && reopened.preset.layers[0].texture != original.layers[0].texture,"Image replacement failed")
        reopened.preset=original;await reopened.rebuild()

        let renderer=try RealityRenderer()
        guard let device=MTLCreateSystemDefaultDevice() else {throw WindowValidationError.invalid("Metal","No device")}
        renderer.cameraSettings.colorBackground = .color(CGColor(gray:0.03,alpha:1))
        renderer.cameraSettings.isToneMappingEnabled=false
        let root=Entity(),camera=PerspectiveCamera();camera.camera.fieldOfViewInDegrees=50
        root.addChild(reopened.stage);root.addChild(camera)
        renderer.activeCamera=camera;renderer.entities.append(root)
        let width=640,height=480
        let desc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm_srgb,width:width,height:height,mipmapped:false)
        desc.storageMode = .shared;desc.usage=[.renderTarget,.shaderRead]
        guard let target=device.makeTexture(descriptor:desc) else {throw WindowValidationError.invalid("Metal","No render target")}
        let cameraOutput=try RealityRenderer.CameraOutput(.singleProjection(colorTexture:target))
        var renders:[[UInt8]]=[]
        var namedRenders:[String:[UInt8]]=[:]
        for (name,position) in [("Front",SIMD3<Float>(0,0,5)),("Oblique",SIMD3<Float>(3.54,0,3.54)),
            ("High",SIMD3<Float>(2,3.1,4)),("Low",SIMD3<Float>(2,-2.6,4)),
            ("Resized",SIMD3<Float>(3,2,5)),("NightCafe",SIMD3<Float>(2.5,0.7,6)),
            ("Hydroponics",SIMD3<Float>(2,0.8,5)),("TransitOval",SIMD3<Float>(2,0,6)),
            ("ListeningLounge",SIMD3<Float>(2,1,5)),
            ("ApartmentEvening",SIMD3<Float>(1.8,1,6)),("ApartmentBlinds",SIMD3<Float>(1.8,1,6)),
            ("CafeTables",SIMD3<Float>(2.5,0.7,6)),("CafeHigh",SIMD3<Float>(2,2.5,5)),
            ("CafeClosed",SIMD3<Float>(2.5,0.7,6)),("Workshift",SIMD3<Float>(1.5,0.6,5.5)),
            ("Standby",SIMD3<Float>(1.5,0.6,5.5)),("Nursery",SIMD3<Float>(1.5,0.6,5)),
            ("AfterHours",SIMD3<Float>(1.2,0.6,5)),("NightWatch",SIMD3<Float>(1.7,0.5,5.5)),
            ("ConnectedApartment",SIMD3<Float>(0,0,13)),("ConnectedOffice",SIMD3<Float>(3,1,13)),
            ("ConnectedWorkshop",SIMD3<Float>(-4,1,13)),("ConnectedOfficeLeft",SIMD3<Float>(-4,0,13)),
            ("ConnectedOfficeRight",SIMD3<Float>(4,0,13)),("Reflections",SIMD3<Float>(1,0,5))] {
            if name=="Resized" {
                reopened.resize(width:5.2,height:3.6)
                try check(reopened.preset.placedLayer(reopened.preset.layers[0]).size == reopened.preset.size,"Curtains must follow the opening size")
                await reopened.rebuild()
            }
            let choices=["ConnectedApartment":"connected_apartment","ConnectedOffice":"connected_office","ConnectedOfficeLeft":"connected_office","ConnectedOfficeRight":"connected_office","ConnectedWorkshop":"connected_workshop","NightCafe":"night_cafe","Hydroponics":"hydroponic","TransitOval":"transit_control","ListeningLounge":"listening_lounge",
                "ApartmentEvening":"apartment_evening","ApartmentBlinds":"apartment_privacy",
                "CafeTables":"cafe_tables","CafeHigh":"cafe_tables","CafeClosed":"cafe_closed",
                "Workshift":"avionics_workshift","Standby":"avionics_standby","Nursery":"hydroponic_dusk",
                "AfterHours":"listening_afterhours","NightWatch":"transit_night"]
            if let id=choices[name] {reopened.choose(id);try check(reopened.preset.id==id,"Preset selection failed: \(id)");await reopened.rebuild()}
            if name=="Reflections" {reopened.reflectionsOnly=true;await reopened.rebuild()}
            try check(reopened.error == nil,"\(name) preview failed: \(reopened.error ?? "")")
            camera.look(at:.zero,from:position,relativeTo:nil)
            for _ in 0..<3 {
                try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
                    do {try renderer.updateAndRender(deltaTime:1/60,cameraOutput:cameraOutput,onComplete:{_ in continuation.resume()})}
                    catch {continuation.resume(throwing:error)}
                }
            }
            var bytes=[UInt8](repeating:0,count:width*height*4)
            bytes.withUnsafeMutableBytes {target.getBytes($0.baseAddress!,bytesPerRow:width*4,from:MTLRegionMake2D(0,0,width,height),mipmapLevel:0)}
            renders.append(bytes)
            namedRenders[name]=bytes
            let data=Data(bytes)
            guard let provider=CGDataProvider(data:data as CFData),
                  let image=CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent),
                  let destination=CGImageDestinationCreateWithURL(output.appendingPathComponent(name+".png") as CFURL,UTType.png.identifier as CFString,1,nil) else {throw WindowValidationError.invalid("image","Cannot write evidence")}
            CGImageDestinationAddImage(destination,image,nil)
            try check(CGImageDestinationFinalize(destination),"Cannot finish image")
        }
        try check(renders[0] != renders[1],"Oblique view did not change")
        let center=(height/2*width+width/2)*4
        try check(Int(renders[0][center])+Int(renders[0][center+1])>20,"Window rendered black")
        func brightness(_ pixels:[UInt8]) -> Double {
            stride(from:0,to:pixels.count,by:4).reduce(0) { $0+Double(pixels[$1])+Double(pixels[$1+1])+Double(pixels[$1+2]) }
        }
        let dimRatio=brightness(namedRenders["Standby"]!)/brightness(namedRenders["Workshift"]!)
        try check(namedRenders["Standby"]! != namedRenders["Workshift"]!,"Standby coverings/emission must change the rendered appearance")
        let workshift=try WindowLibrary.starter().presets.first{$0.id=="avionics_workshift"}!
        let standby=try WindowLibrary.starter().presets.first{$0.id=="avionics_standby"}!
        try check(standby.ambientGain==workshift.ambientGain && standby.highlightGain==workshift.highlightGain,"Standby must not blanket-dim room materials")
        try check((standby.emissionGain ?? 0)<(workshift.emissionGain ?? 0) && (standby.shutter ?? 0)>0,"Standby must use independent emission and privacy controls")
        let summary:[String:Any]=["result":"passed","imageBrightnessRatioInformational":dimRatio,"independentNightEmission":true,"checks":["initial render","property changes","portable preset save/reopen including texture bytes","night and connected-room save/reopen including all referenced emission/texture bytes","invalid settings preserve preview","reset baseline","missing far bake error","four-layer bound","image replacement","native front/oblique/high/low render","resized room and curtains","themed nonrectangular apertures","night-room variants and three connected-room renders","independent emission and privacy without ambient dimming","reflection-only preview"],"UIAutomation":"unavailable; interaction not asserted","headsetExecution":false]
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("Checks.json"))
        print("WINDOW_SHOPPER_CHECKS_PASSED \(output.path)")
    }
}
