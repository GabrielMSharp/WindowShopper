import XCTest
import AppKit
import RealityKit
import Metal
@testable import WindowShopper

@MainActor final class SharedRoomRenderingTests: XCTestCase {
    func testSharedProjectionEmissionAndPrivacy() async throws {
        let directory=URL(fileURLWithPath:"/tmp/WindowShopperSharedRoomPixels")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        for (name,rgba) in [("WindowWhite.png",[255,255,255,255]),("Blue.png",[15,30,100,255]),("Red.png",[240,0,0,255]),("Black.png",[0,0,0,255])] {
            let b=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:2,pixelsHigh:2,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:8,bitsPerPixel:32)!
            for i in 0..<16 {b.bitmapData![i]=UInt8(rgba[i%4])}
            try b.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent(name))
        }
        let renderer=try RealityRenderer(),device=try XCTUnwrap(MTLCreateSystemDefaultDevice())
        renderer.cameraSettings.isToneMappingEnabled=false
        renderer.cameraSettings.colorBackground = .color(CGColor(gray:0,alpha:1))
        let root=Entity(),camera=PerspectiveCamera();camera.camera.fieldOfViewInDegrees=50
        root.addChild(camera);renderer.entities.append(root);renderer.activeCamera=camera
        let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm_srgb,width:384,height:256,mipmapped:false)
        d.storageMode = .shared;d.usage=[.renderTarget,.shaderRead]
        let target=try XCTUnwrap(device.makeTexture(descriptor:d)),output=try RealityRenderer.CameraOutput(.singleProjection(colorTexture:target))
        let resources=WindowResources()
        func render(_ p:WindowPreset,eye:Float=0,elevation:Float=0,fog:Bool=false) async throws -> [UInt8] {
            for child in Array(root.children) where child !== camera {child.removeFromParent()}
            let entity=try await resources.makeWindow(component:.init(id:"shared",presetID:p.id),library:.init(presets:[p]),root:directory)
            func descendants(_ e:Entity)->[Entity] {[e]+e.children.flatMap(descendants)}
            for part in descendants(entity) {
                guard var model=part.components[ModelComponent.self] else {continue}
                model.materials=try model.materials.map {m in
                    var shader=try XCTUnwrap(m as? ShaderGraphMaterial)
                    try shader.setParameter(name:"FogEnabled",value:.float(fog ? 1:0))
                    try shader.setParameter(name:"FogDensity",value:.float(-0.15))
                    return shader
                };part.components.set(model)
            }
            root.addChild(entity);camera.position=[eye,elevation,7]
            for _ in 0..<3 {try await withCheckedThrowingContinuation { (c:CheckedContinuation<Void,Error>) in
                do {try renderer.updateAndRender(deltaTime:1/60,cameraOutput:output,onComplete:{_ in c.resume()})} catch {c.resume(throwing:error)}
            }}
            var pixels=[UInt8](repeating:0,count:384*256*4)
            pixels.withUnsafeMutableBytes{target.getBytes($0.baseAddress!,bytesPerRow:384*4,from:MTLRegionMake2D(0,0,384,256),mipmapLevel:0)}
            return pixels
        }
        func redPoints(_ pixels:[UInt8])->[SIMD2<Float>] {
            var points:[SIMD2<Float>]=[]
            for i in 0..<(384*256) {
                if Int(pixels[i*4])>Int(pixels[i*4+2])+70 {points.append([Float(i%384),Float(i/384)])}
            }
            return points
        }
        var p=WindowPreset(id:"shared",displayName:"Shared",size:[3,2],depth:2,shellTexture:"Blue.png",
                           shellRects:Array(repeating:[0,0,1,1],count:5),layers:[.init(id:"object",texture:"Red.png",depth:1,size:[0.6,0.8],offset:[-1.5,0])],
                           glass:.init(reflectionTexture:"WindowWhite.png",reflectionStrength:0),ambientGain:1,highlightGain:1)
        p.roomSize=[6.3,2];p.apertures=[.init(size:[3,2],offset:[-1.65,0]),.init(size:[3,2],offset:[1.65,0])]
        let front=try await render(p),points=redPoints(front)
        XCTAssertGreaterThan(points.count,50)
        XCTAssertTrue(points.allSatisfy{$0.x<192},"One shared furnishing must not repeat in the second window")
        let left=redPoints(try await render(p,eye:-0.12)),right=redPoints(try await render(p,eye:0.12))
        let disparity=left.map(\.x).reduce(0,+)/Float(left.count)-right.map(\.x).reduce(0,+)/Float(right.count)
        XCTAssertEqual(disparity,(128/tan(25 * .pi/180))*0.24/8,accuracy:1.5)
        let elevated=try await render(p,elevation:1)
        XCTAssertNotEqual(front,elevated,"Elevated projection must change")
        // Dedicated light artwork remains visible with ambient disabled.
        p.layers=[];p.ambientGain=0;p.highlightGain=0;p.emissionTexture="Red.png";p.emissionGain=2
        let lit=try await render(p)
        XCTAssertGreaterThan(redPoints(lit).count,1000)
        let fogged=try await render(p,fog:true)
        XCTAssertLessThan(fogged.enumerated().filter{$0.offset%4==0}.reduce(0){$0+Int($1.element)},lit.enumerated().filter{$0.offset%4==0}.reduce(0){$0+Int($1.element)})
        p.apertures![0].shutter=1
        let covered=redPoints(try await render(p))
        XCTAssertTrue(covered.allSatisfy{$0.x>192},"A shutter must occlude emissive artwork in its own opening")
        p.layers=[.init(id:"occluder",texture:"Black.png",depth:0.2,size:[20,20])]
        let occluded=try await render(p)
        XCTAssertTrue(redPoints(occluded).isEmpty,"Opaque foreground must occlude rear-wall emission")
        p.layers=[];p.emissionGain=0
        let unlit=try await render(p)
        XCTAssertTrue(redPoints(unlit).isEmpty)
        // Three apertures use the same projection and retain individual privacy.
        p.roomSize=[9.6,2];p.apertures=[.init(size:[3,2],offset:[-3.3,0]),.init(size:[3,2]),.init(size:[3,2],offset:[3.3,0])]
        p.emissionGain=2;p.apertures![1].shutter=1
        let triple=try await render(p)
        XCTAssertGreaterThan(redPoints(triple).count,100)
    }
}
