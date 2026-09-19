import SwiftUI
import WindowShopper
import UniformTypeIdentifiers

struct DemoView: View {
    @Bindable var lab:DemoModel
    @State private var importing=false
    @State private var importTarget:ImageTarget?
    @State private var exporting=false
    @State private var document:DemoDocument?
    var body:some View {
        HStack(spacing:0) {
            VStack(spacing:0) {
                HStack {
                    VStack(alignment:.leading) {
                        Text("Window Shopper").font(.title2.bold())
                        Text("Isolated RealityKit window renderer").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open…") {importTarget=nil;importing=true}
                    Button("Save As…") {
                        do {document=try lab.document();exporting=true} catch {lab.error=String(describing:error)}
                    }
                }.padding()
                WindowViewport(lab:lab).frame(minWidth:400,minHeight:300)
                #if os(macOS)
                CameraControls(lab:lab).padding()
                #endif
                VStack(alignment:.leading,spacing:5) {
                    HStack {
                        if lab.busy {ProgressView().controlSize(.small)}
                        Text(lab.status)
                        Spacer()
                        Text("\(lab.textureCount) cached textures · last rebuild \(lab.lastBuildMilliseconds,specifier:"%.1f") ms")
                    }.font(.caption)
                    if let error=lab.error {
                        Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled)
                    }
                }.padding().frame(maxWidth:.infinity,alignment:.leading).background(.quaternary.opacity(0.4))
            }
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    Picker("Preset",selection:Binding(get:{lab.selectedPreset},set:{lab.choose($0)})) {
                        ForEach(lab.library,id:\.id) {Text($0.displayName).tag($0.id)}
                        if lab.selectedPreset=="custom" {Text("Loaded preset").tag("custom")}
                    }
                    TextField("Preset name",text:$lab.preset.displayName)
                    HStack {
                        Button("Reset preset") {lab.reset()}
                        Spacer()
                        Picker("Quality",selection:$lab.quality) {
                            Text("Full").tag(WindowQuality.full)
                            Text("Reduced").tag(WindowQuality.reduced)
                            Text("Baked").tag(WindowQuality.baked)
                        }.labelsHidden()
                    }
                    GroupBox("Room") {
                        VStack(spacing:10) {
                            Picker("Opening shape",selection:Binding(get:{lab.preset.shape ?? .rectangle},set:{lab.preset.shape=$0})) {
                                ForEach(WindowShape.allCases,id:\.self) {Text($0.rawValue.capitalized).tag($0)}
                            }
                            LabNumber("Width (m)",value:Binding(get:{lab.preset.size.x},set:{lab.resize(width:$0)}),range:0.3...8)
                            LabNumber("Height (m)",value:Binding(get:{lab.preset.size.y},set:{lab.resize(height:$0)}),range:0.3...6)
                            LabNumber("Depth (m)",value:$lab.preset.depth,range:0.15...8)
                            LabNumber("Surface tile width (m)",value:Binding(get:{lab.preset.surfaceTileSize?.x ?? 3},set:{lab.preset.surfaceTileSize=[$0,lab.preset.surfaceTileSize?.y ?? 3]}),range:0.2...8)
                            LabNumber("Surface tile height (m)",value:Binding(get:{lab.preset.surfaceTileSize?.y ?? 3},set:{lab.preset.surfaceTileSize=[lab.preset.surfaceTileSize?.x ?? 3,$0]}),range:0.2...8)
                            Button("Replace back-wall atlas…") {pick(.shell)}
                            Button("Replace side/floor/ceiling atlas…") {pick(.surfaces)}
                            Text(lab.preset.shellTexture).font(.caption2).lineLimit(1)
                            DisclosureGroup("Shell UV rectangles") {
                                ForEach(0..<5,id:\.self) {i in
                                    UVControls(title:["Back","Left","Right","Floor","Ceiling"][i],rect:$lab.preset.shellRects[i])
                                }
                            }
                        }.padding(5)
                    }
                    GroupBox("Shared room and privacy") {
                        VStack(spacing:10) {
                            Picker("Openings",selection:Binding(get:{lab.preset.apertures?.count ?? 1},set:{lab.setApertureCount($0)})) {
                                ForEach(1...4,id:\.self) {Text("\($0)").tag($0)}
                            }
                            LabNumber("Room width (m)",value:Binding(get:{lab.preset.interiorSize.x},set:{lab.resizeRoom(width:$0)}),range:0.3...20)
                            LabNumber("Room height (m)",value:Binding(get:{lab.preset.interiorSize.y},set:{lab.resizeRoom(height:$0)}),range:0.3...8)
                            if lab.preset.apertures != nil {
                                ForEach(0..<(lab.preset.apertures?.count ?? 0),id:\.self) {i in
                                    DisclosureGroup("Opening \(i+1)") {
                                        LabNumber("Width",value:Binding(get:{lab.preset.apertures![i].size.x},set:{lab.preset.apertures![i].size.x=$0}),range:0.3...8)
                                        LabNumber("Height",value:Binding(get:{lab.preset.apertures![i].size.y},set:{lab.preset.apertures![i].size.y=$0}),range:0.3...8)
                                        LabNumber("Vertical position",value:Binding(get:{lab.preset.apertures![i].offset.y},set:{lab.preset.apertures![i].offset.y=$0}),range:-4...4)
                                        LabNumber("Horizontal position",value:Binding(get:{lab.preset.apertures![i].offset.x},set:{lab.preset.apertures![i].offset.x=$0}),range:-10...10)
                                        LabNumber("Shutter coverage",value:Binding(get:{lab.preset.apertures![i].shutter},set:{lab.preset.apertures![i].shutter=$0}),range:0...1)
                                        Toggle("Vertical divider",isOn:Binding(get:{lab.preset.apertures![i].mullion},set:{lab.preset.apertures![i].mullion=$0}))
                                        Toggle("Cross beam",isOn:Binding(get:{lab.preset.apertures![i].crossbar},set:{lab.preset.apertures![i].crossbar=$0}))
                                    }
                                }
                            } else {
                                LabNumber("Shutter coverage",value:Binding(get:{lab.preset.shutter ?? 0},set:{lab.preset.shutter=$0}),range:0...1)
                                Toggle("Vertical divider",isOn:Binding(get:{lab.preset.mullion ?? false},set:{lab.preset.mullion=$0}))
                                Toggle("Cross beam",isOn:Binding(get:{lab.preset.crossbar ?? false},set:{lab.preset.crossbar=$0}))
                            }
                            LabNumber("Practical light emission",value:Binding(get:{lab.preset.emissionGain ?? 0},set:{lab.preset.emissionGain=$0}),range:0...8)
                            Button("Replace emission artwork…") {pick(.emission)}
                        }.padding(5)
                    }
                    SofaControls(sofa:$lab.preset.sofa)
                    HStack {
                        Text("Image layers (\(lab.preset.layers.count)/4)").font(.headline)
                        Spacer();Button("Add",systemImage:"plus") {lab.addLayer()}.disabled(lab.preset.layers.count>=4)
                    }
                    Text("Layers are composited from far to near. List order breaks ties at equal depth.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach($lab.preset.layers,id:\.id) { $layer in
                        let layerID=layer.id
                        WindowLayerControls(layer:$layer,depth:lab.preset.depth,
                            replace:{pick(.layer(layerID))},remove:{lab.preset.layers.removeAll{$0.id==layerID}},
                            move:{delta in if let i=lab.preset.layers.firstIndex(where:{$0.id==layerID}){lab.moveLayer(i,delta)}})
                    }
                    GroupBox("Glass") {
                        VStack(spacing:10) {
                            LabNumber("Reflection",value:$lab.preset.glass.reflectionStrength,range:0...1)
                            LabNumber("Reflection exposure",value:Binding(get:{lab.preset.glass.exposure ?? 1},set:{lab.preset.glass.exposure=$0}),range:0...8)
                            LabNumber("Environment rotation (°)",value:Binding(get:{lab.preset.glass.rotationDegrees ?? 0},set:{lab.preset.glass.rotationDegrees=$0}),range:-180...180)
                            LabNumber("Reflection blur",value:Binding(get:{lab.preset.glass.roughness ?? 0},set:{lab.preset.glass.roughness=$0}),range:0...1)
                            Toggle("Reflections only (debug)",isOn:$lab.reflectionsOnly)
                            TintControls(tint:$lab.preset.glass.tint)
                            Button("Replace reflection image…") {pick(.reflection)}
                            Text("Equirectangular environment image").font(.caption).foregroundStyle(.secondary)
                        }.padding(5)
                    }
                    GroupBox("Lighting and diagnostics") {
                        VStack(spacing:10) {
                            LabNumber("Ambient gain",value:$lab.preset.ambientGain,range:0...1)
                            LabNumber("Highlight gain",value:$lab.preset.highlightGain,range:0...1)
                            Toggle("Physical frame",isOn:$lab.frames)
                            Toggle("Headlight",isOn:$lab.headlights)
                            Toggle("City fog",isOn:$lab.fog)
                            if lab.fog {
                                LabNumber("Density",value:$lab.fogDensity,range:0...0.08)
                                LabNumber("Brightness",value:$lab.fogBrightness,range:0...1.5)
                            }
                            #if os(macOS)
                            Toggle("Renderer statistics",isOn:$lab.statistics)
                            #endif
                            Button("Load baked far appearance…") {pick(.baked)}
                            Text("Baked quality needs a flattened image when layers or a sofa are present. Errors keep the last valid preview visible.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(5)
                    }
                }.padding(18)
            }.frame(width:370)
        }
        .frame(minWidth:850,minHeight:650)
        .task(id:lab.buildKey) {await lab.rebuild()}
        .task {
            if let option=ProcessInfo.processInfo.arguments.firstIndex(of:"--capture-gif"),
               ProcessInfo.processInfo.arguments.indices.contains(option+1) {
                do {
                    try await DemoChecks.captureGIF(
                        at:URL(fileURLWithPath:ProcessInfo.processInfo.arguments[option+1]))
                    exit(0)
                } catch {
                    FileHandle.standardError.write(Data("WINDOW_SHOPPER_GIF_FAILED \(error)\n".utf8));exit(1)
                }
            }
            if ProcessInfo.processInfo.arguments.contains("--self-test") {
                do {try await DemoChecks.run();exit(0)}
                catch {FileHandle.standardError.write(Data("WINDOW_SHOPPER_CHECKS_FAILED \(error)\n".utf8));exit(1)}
            }
        }
        .fileImporter(isPresented:$importing,allowedContentTypes:importTarget==nil ? [.json]:[.image],allowsMultipleSelection:false) {result in
            do {
                guard let url=try result.get().first else {return}
                if let target=importTarget {try lab.importImage(url,for:target)} else {try lab.load(url)}
            } catch {lab.error=String(describing:error)}
        }
        .fileExporter(isPresented:$exporting,document:document,contentType:.json,defaultFilename:lab.preset.displayName+".windowlab") {result in
            if case .failure(let error)=result {lab.error=String(describing:error)}
        }
    }
    private func pick(_ target:ImageTarget) {importTarget=target;importing=true}
}

struct LabNumber:View {
    var title:String
    @Binding var value:Float
    var range:ClosedRange<Float>
    init(_ title:String,value:Binding<Float>,range:ClosedRange<Float>) {self.title=title;_value=value;self.range=range}
    var body:some View {
        VStack(spacing:3) {
            HStack {Text(title);Spacer();TextField(title,value:$value,format:.number.precision(.fractionLength(2))).labelsHidden().multilineTextAlignment(.trailing).frame(width:65)}
            Slider(value:$value,in:range).labelsHidden().accessibilityLabel(title)
        }.font(.caption)
    }
}
struct TintControls:View {
    @Binding var tint:SIMD3<Float>
    var body:some View {
        DisclosureGroup("Tint") {
            LabNumber("Red",value:$tint.x,range:0...1)
            LabNumber("Green",value:$tint.y,range:0...1)
            LabNumber("Blue",value:$tint.z,range:0...1)
        }
    }
}
struct UVControls:View {
    var title:String
    @Binding var rect:SIMD4<Float>
    var body:some View {
        VStack(alignment:.leading) {
            Text(title).font(.caption.bold())
            HStack {
                TextField("Min U",value:$rect.x,format:.number.precision(.fractionLength(3)))
                TextField("Min V",value:$rect.y,format:.number.precision(.fractionLength(3)))
                TextField("Max U",value:$rect.z,format:.number.precision(.fractionLength(3)))
                TextField("Max V",value:$rect.w,format:.number.precision(.fractionLength(3)))
            }.textFieldStyle(.roundedBorder)
        }
    }
}
struct WindowLayerControls:View {
    @Binding var layer:WindowLayer
    var depth:Float
    var replace:()->Void
    var remove:()->Void
    var move:(Int)->Void
    var body:some View {
        GroupBox {
            VStack(spacing:9) {
                HStack {
                    Text(layer.id).font(.headline);Spacer()
                    Button {move(-1)} label:{Image(systemName:"arrow.up")}.help("Move earlier at equal depth")
                    Button {move(1)} label:{Image(systemName:"arrow.down")}.help("Move later at equal depth")
                    Button(role:.destructive,action:remove) {Image(systemName:"trash")}
                }
                HStack {Button("Replace image…",action:replace);Spacer()}
                Text(layer.texture).font(.caption2).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading)
                Picker("Anchor",selection:Binding(get:{layer.anchor ?? .free},set:{layer.anchor=$0})) {
                    Text("Free placement").tag(WindowLayerAnchor.free)
                    Text("Floor").tag(WindowLayerAnchor.floor)
                    Text("Ceiling").tag(WindowLayerAnchor.ceiling)
                    Text("Fit opening").tag(WindowLayerAnchor.fitWindow)
                }
                LabNumber("Depth (m)",value:$layer.depth,range:0...max(0.01,depth-0.01))
                LabNumber("Width (m)",value:$layer.size.x,range:0.05...10).disabled(layer.anchor == .fitWindow)
                LabNumber("Height (m)",value:$layer.size.y,range:0.05...8).disabled(layer.anchor == .fitWindow)
                LabNumber("Horizontal offset",value:$layer.offset.x,range:-4...4)
                LabNumber(layer.anchor == .floor ? "Floor clearance":"Vertical offset",value:$layer.offset.y,range:-4...4)
                LabNumber("Opacity",value:$layer.opacity,range:0...1)
                TintControls(tint:$layer.tint)
                DisclosureGroup("Image UV crop") {UVControls(title:"Bottom-left origin",rect:$layer.uvRect)}
            }.padding(5)
        }
    }
}
struct CameraControls:View {
    @Bindable var lab:DemoModel
    var body:some View {
        VStack(spacing:10) {
            HStack {
                Button("Front") {lab.yaw=0;lab.pitch=0;lab.eyeOffset=0}
                Button("Left 45°") {lab.yaw = -45;lab.pitch=0}
                Button("Right 45°") {lab.yaw=45;lab.pitch=0}
                Button("High") {lab.pitch=35;lab.yaw=20}
                Button("Low") {lab.pitch = -25;lab.yaw=20}
                Toggle("Sweep",isOn:$lab.sweep).toggleStyle(.button)
            }
            HStack(spacing:18) {
                LabNumber("Orbit (°)",value:$lab.yaw,range:-80...80)
                LabNumber("Elevation (°)",value:$lab.pitch,range:-45...45)
                LabNumber("Distance (m)",value:$lab.distance,range:1...12)
                LabNumber("Eye offset (m)",value:$lab.eyeOffset,range:-0.12...0.12)
            }
        }.task(id:lab.sweep) {
            guard lab.sweep else {return}
            let start=ContinuousClock.now
            while !Task.isCancelled {
                let t=start.duration(to:.now);let seconds=Double(t.components.seconds)+Double(t.components.attoseconds)/1e18
                lab.yaw=Float(sin(seconds*0.45)*65)
                do {try await Task.sleep(for:.milliseconds(33))} catch {return}
            }
        }
    }
}

struct SofaControls:View {
    @Binding var sofa:WindowSofa?
    func field<T>(_ keyPath:WritableKeyPath<WindowSofa,T>) -> Binding<T> {
        Binding(get:{(sofa ?? .init())[keyPath:keyPath]},set:{value in var item=sofa ?? .init();item[keyPath:keyPath]=value;sofa=item})
    }
    var body:some View {
        GroupBox("Solid calibration furniture") {
            VStack(spacing:10) {
                Toggle("Floor-mounted sofa",isOn:Binding(get:{sofa != nil},set:{sofa=$0 ? .init():nil}))
                if sofa != nil {
                    LabNumber("Sofa width",value:field(\.size.x),range:0.3...4)
                    LabNumber("Sofa height",value:field(\.size.y),range:0.3...1.5)
                    LabNumber("Sofa depth",value:field(\.size.z),range:0.3...1.5)
                    LabNumber("Distance behind window",value:field(\.frontDepth),range:0.05...4)
                    LabNumber("Horizontal position",value:field(\.horizontalOffset),range:-3...3)
                    TintControls(tint:field(\.tint))
                    Text("Solid ray-box surfaces with floor-contacting feet. Automatically fits inside smaller rooms. The room is still rendered on one opaque surface.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(5)
        }
    }
}
