import SwiftUI
import RealityKit
#if os(macOS)
import AppKit
struct WindowViewport: View {
    var lab:DemoModel
    var body:some View {
        MacWindowSurface(lab:lab,yaw:lab.yaw,pitch:lab.pitch,distance:lab.distance,eyeOffset:lab.eyeOffset,statistics:lab.statistics)
    }
}
private struct MacWindowSurface: NSViewRepresentable {
    var lab:DemoModel
    var yaw:Float
    var pitch:Float
    var distance:Float
    var eyeOffset:Float
    var statistics:Bool
    func makeNSView(context:Context)->ARView {
        let view=ARView(frame:.zero)
        view.environment.background = .color(.init(red:0.035,green:0.047,blue:0.065,alpha:1))
        let anchor=AnchorEntity(world:.zero)
        anchor.addChild(lab.stage);anchor.addChild(lab.camera);view.scene.addAnchor(anchor)
        lab.updateCamera()
        return view
    }
    func updateNSView(_ view:ARView,context:Context) {
        lab.updateCamera()
        view.debugOptions=statistics ? [.showStatistics]:[]
    }
}
#else
struct WindowViewport: View {
    var lab:DemoModel
    @Environment(\.openImmersiveSpace) private var openSpace
    @Environment(\.dismissImmersiveSpace) private var closeSpace
    @State private var open=false
    var body:some View {
        VStack(spacing:20) {
            Image(systemName:"view.3d").font(.system(size:54))
            Text("Inspect at physical scale").font(.title2)
            Text("Open the window in your space, then move your head to check stereo depth and oblique views.")
                .multilineTextAlignment(.center).frame(maxWidth:380)
            Button(open ? "Close spatial preview":"Open spatial preview") {
                Task {
                    if open {await closeSpace();open=false}
                    else {if case .opened = await openSpace(id:"WindowShopperSpace") {open=true}}
                }
            }.buttonStyle(.borderedProminent)
            Text("3 metres ahead · centred at 1.4 metres high").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
    }
}
#endif
