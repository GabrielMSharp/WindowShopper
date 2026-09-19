import SwiftUI
import RealityKit

@main struct WindowShopperDemoApp: App {
    @State private var lab = DemoModel()
    var body: some SwiftUI.Scene {
        WindowGroup {
            DemoView(lab:lab)
        }
        .defaultSize(width:1200,height:820)
        #if os(visionOS)
        ImmersiveSpace(id:"WindowShopperSpace") {
            RealityView { content in
                content.add(lab.stage)
                lab.stage.position=[0,1.4,-3]
            }
        }.immersionStyle(selection:.constant(.mixed),in:.mixed)
        #endif
    }
}
