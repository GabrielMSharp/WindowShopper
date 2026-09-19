import XCTest
import AppKit
import RealityKit
import Metal
@testable import WindowShopper

@MainActor final class WindowRenderingTests: XCTestCase {
    func testNativeLayerCompositingAndParallax() async throws {
        let root=URL(fileURLWithPath:"/tmp/WindowShopperWindowPixels")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        func texture(_ name:String,_ rgba:[UInt8]) throws {
            let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:2,pixelsHigh:2,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:8,bitsPerPixel:32)!
            for i in 0..<16 {bitmap.bitmapData![i]=rgba[i%4]}
            try bitmap.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(name))
        }
        try texture("WindowWhite.png",[255,255,255,255])
        try texture("Shell.png",[30,50,120,255])
        try texture("Red.png",[240,15,15,255])
        try texture("Green.png",[15,240,15,128])
        var p=WindowPreset(id:"fixture",displayName:"Fixture",size:[3,2],depth:2,
                           shellTexture:"Shell.png",shellRects:Array(repeating:[0,0,1,1],count:5),
                           layers:[.init(id:"red",texture:"Red.png",depth:1,size:[0.6,1])],
                           glass:.init(reflectionTexture:"WindowWhite.png",reflectionStrength:0),ambientGain:1,highlightGain:1)
        let resources=WindowResources()
        let renderer=try RealityRenderer(),device=try XCTUnwrap(MTLCreateSystemDefaultDevice())
        renderer.cameraSettings.colorBackground = .color(CGColor(gray:0,alpha:1));renderer.cameraSettings.isToneMappingEnabled=false
        let scene=Entity(),camera=PerspectiveCamera();camera.camera.fieldOfViewInDegrees=50
        scene.addChild(camera);renderer.activeCamera=camera;renderer.entities.append(scene)
        let panel=try await resources.makeWindow(component:.init(id:"panel",presetID:p.id),library:.init(presets:[p]),root:root)
        panel.position=[0,0,-3];scene.addChild(panel)
        let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm_srgb,width:256,height:256,mipmapped:false)
        d.storageMode = .shared;d.usage=[.renderTarget,.shaderRead]
        let target=try XCTUnwrap(device.makeTexture(descriptor:d)),output=try RealityRenderer.CameraOutput(.singleProjection(colorTexture:target))
        func render(_ preset:WindowPreset,eye:Float=0,quality:WindowQuality = .full) async throws -> [UInt8] {
            // Finish fallible async compilation before opening RealityKit's
            // model accessor; do not suspend or throw during an inout mutation.
            let material=try await resources.material(preset:preset,root:root,quality:quality,fogEnabled:false)
            var model=try XCTUnwrap(panel.model)
            model.materials=[material];panel.model=model
            camera.position.x=eye
            for _ in 0..<3 {try await withCheckedThrowingContinuation { (c:CheckedContinuation<Void,Error>) in
                do {try renderer.updateAndRender(deltaTime:1/60,cameraOutput:output,onComplete:{_ in c.resume()})}catch{c.resume(throwing:error)}
            }}
            var bytes=[UInt8](repeating:0,count:256*256*4)
            bytes.withUnsafeMutableBytes{target.getBytes($0.baseAddress!,bytesPerRow:1024,from:MTLRegionMake2D(0,0,256,256),mipmapLevel:0)}
            return bytes
        }
        let base=try await render(p)
        XCTAssertEqual(Int(base[(128*256+165)*4+2]),120,accuracy:5,"Colour textures must retain their authored sRGB appearance")
        let mid=(128*256+128)*4
        XCTAssertGreaterThan(base[mid],base[mid+2]+80,"Opaque red foreground must cover blue shell")
        // Measure disparity, not just different images: a layer one metre behind
        // the panel must project at four metres, rather than sliding with its face.
        func redCentroid(_ pixels: [UInt8]) throws -> Float {
            var sum: Float=0, count: Float=0
            for y in 0..<256 { for x in 0..<256 {
                let i=(y*256+x)*4
                if Int(pixels[i]) > Int(pixels[i+1])+80 && Int(pixels[i]) > Int(pixels[i+2])+80 {
                    sum += Float(x); count += 1
                }
            }}
            XCTAssertGreaterThan(count,100)
            return sum/max(count,1)
        }
        let eyeLeft=try await render(p,eye:-0.12),eyeRight=try await render(p,eye:0.12)
        let measured=try redCentroid(eyeLeft)-redCentroid(eyeRight)
        let focal: Float=128/tan(25 * .pi/180)
        XCTAssertEqual(measured,focal*0.24/4,accuracy:1.5,"Layer must project at its virtual depth")
        for (name,pixels) in [("WindowFront",base),("WindowLeft",eyeLeft),("WindowRight",eyeRight)] {
            let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:256,pixelsHigh:256,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:1024,bitsPerPixel:32)!
            pixels.withUnsafeBytes { bitmap.bitmapData!.update(from:$0.baseAddress!.assumingMemoryBound(to:UInt8.self),count:pixels.count) }
            try bitmap.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(name+".png"))
        }
        // A second image with alpha blends INSIDE the opaque surface.
        p.layers.append(.init(id:"green",texture:"Green.png",depth:0.2,size:[0.6,1]))
        let layered=try await render(p)
        XCTAssertGreaterThan(layered[mid+1],base[mid+1]+50)
        XCTAssertEqual(layered[mid+3],255)
        let left=try await render(p,eye:-0.12),right=try await render(p,eye:0.12)
        XCTAssertNotEqual(left,right,"View-dependent sampling must respond to viewpoint translation")
        // An oversized layer must be hidden where the ray hits a side wall
        // before reaching it, even though its image rectangle covers that ray.
        p.layers=[.init(id:"oversized",texture:"Red.png",depth:1,size:[20,20])]
        camera.look(at:[0,0,-3],from:[6,0,0],relativeTo:nil)
        let oblique=try await render(p,eye:6)
        XCTAssertGreaterThan(oblique[mid+2],oblique[mid]+25,"Side wall must occlude the layer")
        camera.orientation = .init()
        // Compile/render every bounded graph, including the baked fallback.
        for count in 0...4 {
            p.layers=(0..<count).map{.init(id:"L\($0)",texture:"Red.png",depth:Float($0+1)*0.3,size:[0.5,0.5])}
            _ = try await render(p)
        }
        for count in 0...4 {
            p.sofa = .init(tint:[0.9,0.3,0.1])
            p.layers=(0..<count).map{.init(id:"S\($0)",texture:"Green.png",depth:Float($0+1)*0.3,size:[0.5,0.5])}
            _ = try await render(p)
        }
        p.sofa=nil
        _ = try await render(p,quality:.reduced)
        do {
            _ = try await render(p,quality:.baked)
            XCTFail("A layered preset must not silently lose its furniture in the far tier")
        } catch is WindowValidationError {}
        p.bakedAppearance = .init(texture:"Shell.png")
        _ = try await render(p,quality:.baked)
        XCTAssertEqual(resources.textureCount,4,"Instances and tiers must share texture resources")
    }
}
