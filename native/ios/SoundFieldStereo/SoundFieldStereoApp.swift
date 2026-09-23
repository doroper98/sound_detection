import SwiftUI

@main
struct SoundFieldStereoApp: App {
    @StateObject private var capture = CaptureModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            CaptureView(model: capture)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    // Permission dialogs also cause .inactive. Cancelling there
                    // would prevent the initial permission grant from working.
                    if phase == .background { capture.enteredBackground() }
                }
        }
    }
}
