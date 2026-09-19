import XCTest
@testable import WindowShopper

final class WindowDefinitionTests: XCTestCase {
    func testCityCatalogAndFittedLayers() throws {
        let library=try WindowLibrary.starter(),bakes=try WindowPresetCatalog.bakes()
        XCTAssertEqual(WindowPresetCatalog.ids.count,15)
        for residential in [true,false] {
            for host in ["Residential_1","Service_27","District_4"] {
                let ids=(0..<3).map{WindowPresetCatalog.presetID(host:host,ordinal:$0,residential:residential)}
                XCTAssertEqual(Set(ids).count,3)
                XCTAssertEqual(ids[0],WindowPresetCatalog.presetID(host:host,ordinal:0,residential:residential))
            }
        }
        for id in WindowPresetCatalog.ids {
            let original=try XCTUnwrap(library.presets.first{$0.id==id})
            XCTAssertNotNil(bakes.rects[id])
            for size:SIMD2<Float> in [[1.2,2.8],[4.2,1.5],[3.2,2.86]] {
                let fitted=WindowPresetCatalog.fitted(original,size:size)
                try fitted.validate()
                XCTAssertEqual(fitted.size,size)
                for layer in fitted.layers {
                    let placed=fitted.placedLayer(layer)
                    if layer.anchor == .fitWindow {XCTAssertEqual(placed.size,size)}
                    else {XCTAssertLessThanOrEqual(abs(placed.offset.x)+placed.size.x/2,size.x/2+0.001)}
                    if layer.anchor == .floor {XCTAssertEqual(placed.offset.y-placed.size.y/2,-size.y/2,accuracy:0.001)}
                }
            }
        }
    }
    func testNightArtworkIsNotGloballyDimmed() throws {
        let library=try WindowLibrary.starter()
        for original in library.presets where WindowPresetCatalog.ids.contains(original.id) {
            let night=WindowPresetCatalog.nightAppearance(original)
            XCTAssertEqual(night,original)
            XCTAssertEqual(night.ambientGain,1)
            XCTAssertEqual(night.highlightGain,1)
            XCTAssertEqual(night.shellTexture,"WindowNightRooms.png")
            XCTAssertNotNil(night.emissionTexture)
            XCTAssertEqual(night.layers,original.layers)
            XCTAssertEqual(library.presets.first{$0.id==original.id},original)
        }
    }
    func preset() -> WindowPreset {
        .init(id:"test",displayName:"Test",size:[3,2],depth:2,shellTexture:"Shell.png",
              shellRects:Array(repeating:[0,0,1,1],count:5),glass:.init(reflectionTexture:"Reflection.png"))
    }
    func testInvalidRoomAndResourcesRejected() throws {
        var p=preset(); p.depth = .nan; XCTAssertThrowsError(try p.validate())
        p=preset(); p.shellTexture="../outside.png"; XCTAssertThrowsError(try p.validate())
        p=preset(); p.shellRects[0]=[0,0,2,1]; XCTAssertThrowsError(try p.validate())
        p=preset(); p.layers=[.init(id:"bad",texture:"a.png",depth:2,size:[1,1])]
        XCTAssertThrowsError(try p.validate())
    }
    func testLayerLimitAndIdentity() throws {
        var p=preset()
        p.layers=(0..<4).map { .init(id:"layer\($0)",texture:"a.png",depth:Float($0)/4,size:[1,1]) }
        XCTAssertNoThrow(try p.validate())
        p.layers.append(p.layers[0]); XCTAssertThrowsError(try p.validate())
    }
    func testOverrideRoundTripDoesNotMutatePreset() throws {
        let base=preset(); var changed=base;changed.depth=1
        let component=WindowComponent(id:"instance",presetID:base.id,override:changed)
        let decoded=try JSONDecoder().decode(WindowComponent.self,from:JSONEncoder().encode(component))
        let library=WindowLibrary(presets:[base])
        XCTAssertEqual(try decoded.resolved(in:library).depth,1)
        XCTAssertEqual(library.presets[0].depth,2)
        var reset=decoded;reset.override=nil
        XCTAssertEqual(try reset.resolved(in:library),base)
    }
    func testAnchorsAndSofaFollowResizedRoom() throws {
        var p=preset();p.size=[5,4]
        let floor=WindowLayer(id:"floor",texture:"a.png",depth:1,size:[1,1.2],anchor:.floor)
        XCTAssertEqual(p.placedLayer(floor).offset.y,-1.4,accuracy:0.001)
        let fit=WindowLayer(id:"curtain",texture:"a.png",depth:0.1,size:[1,1],anchor:.fitWindow)
        XCTAssertEqual(p.placedLayer(fit).size,p.size)
        p.sofa = .init();p.size=[0.6,0.8];p.depth=0.4
        let sofa=try XCTUnwrap(p.fittedSofa)
        XCTAssertLessThan(sofa.size.x,p.size.x)
        XCTAssertLessThan(sofa.size.y,p.size.y)
        XCTAssertLessThan(sofa.frontDepth+sofa.size.z,p.depth)
        p.depth=0.001
        let shallowSofa=try XCTUnwrap(p.fittedSofa)
        XCTAssertLessThan(shallowSofa.frontDepth+shallowSofa.size.z,p.depth)
    }
    func testAllShapesStayInsideResizedOpening() {
        for shape in WindowShape.allCases {
            let points=WindowGeometry.outline(size:[4,1.5],shape:shape)
            XCTAssertGreaterThanOrEqual(points.count,4)
            XCTAssertTrue(points.allSatisfy{abs($0.x)<=2.001 && abs($0.y)<=0.751})
            var area:Float=0
            for i in points.indices {let a=points[i],b=points[(i+1)%points.count];area += a.x*b.y-b.x*a.y}
            XCTAssertGreaterThan(area,0,"Aperture must face outward")
        }
    }
    func testBundledThemedPresetsDecode() throws {
        let library=try WindowLibrary.starter()
        XCTAssertGreaterThanOrEqual(library.presets.count,10)
        XCTAssertNotNil(library.presets.first{$0.id=="night_cafe"})
    }
    func testDressedRoomsKeepLayerBudgetsAndResources() throws {
        let library=try WindowLibrary.starter()
        let ids=["apartment_evening","apartment_privacy","cafe_tables","cafe_closed","avionics_workshift","avionics_standby","hydroponic_dusk","listening_afterhours","transit_night"]
        for id in ids {
            let p=try XCTUnwrap(library.presets.first{$0.id==id})
            XCTAssertEqual(p.layers.count,2)
            XCTAssertEqual(p.layers.filter{$0.anchor == .floor}.count,2)
            XCTAssertTrue(p.resourceNames.contains("WindowNightEmission.png"))
            for layer in p.layers {
                XCTAssertTrue(FileManager.default.fileExists(atPath:WindowLibrary.starterResourceRoot.appendingPathComponent(layer.texture).path))
                if layer.anchor == .floor {
                    XCTAssertEqual(p.placedLayer(layer).offset.y-layer.size.y/2,-p.size.y/2,accuracy:0.0001)
                }
            }
        }
        let bright=try XCTUnwrap(library.presets.first{$0.id=="avionics_workshift"})
        let dim=try XCTUnwrap(library.presets.first{$0.id=="avionics_standby"})
        XCTAssertEqual(bright.layers,dim.layers)
        XCTAssertEqual(dim.ambientGain,bright.ambientGain)
        XCTAssertLessThan(dim.emissionGain!,bright.emissionGain!)
        XCTAssertGreaterThan(dim.shutter!,bright.shutter!)
        XCTAssertEqual(library.presets.first{$0.id=="night_cafe"}?.layers.count,0,"Keep the undressed comparison preset")
    }
    func testSharedRoomAndEmissionRoundTripAndValidation() throws {
        var p=preset();p.roomSize=[9.6,2];p.emissionTexture="Lights.png";p.emissionGain=2
        p.apertures=[.init(size:[3,2],offset:[-3.3,0],shutter:0.5),.init(size:[3,2]),.init(size:[3,2],offset:[3.3,0],mullion:true)]
        try p.validate()
        let restored=try JSONDecoder().decode(WindowPreset.self,from:JSONEncoder().encode(p))
        XCTAssertEqual(restored,p);XCTAssertTrue(restored.resourceNames.contains("Lights.png"))
        p.apertures![0].offset.x = -5;XCTAssertThrowsError(try p.validate())
        p=preset();p.emissionGain = .nan;XCTAssertThrowsError(try p.validate())
        p=preset();p.shutter=1.1;XCTAssertThrowsError(try p.validate())
        var json=try JSONSerialization.jsonObject(with:JSONEncoder().encode(preset())) as! [String:Any]
        for key in ["roomSize","apertures","apertureOffset","emissionTexture","emissionGain","shutter","mullion","crossbar"] {json.removeValue(forKey:key)}
        let old=try JSONDecoder().decode(WindowPreset.self,from:JSONSerialization.data(withJSONObject:json))
        XCTAssertEqual(old.interiorSize,old.size);XCTAssertNil(old.apertures);XCTAssertNil(old.emissionTexture)
    }

}
