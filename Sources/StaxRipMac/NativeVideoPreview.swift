import SwiftUI
import AVKit

// Bridge the AppKit player directly. The SwiftUI VideoPlayer overlay crashed
// during generic class metadata initialization on the local macOS 27 runtime.
struct NativeVideoPreview: NSViewRepresentable {
    let player: AVPlayer
    var comparisonControls = false

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.showsFullScreenToggleButton = !comparisonControls
        if comparisonControls {
            view.showsFrameSteppingButtons = true
            view.showsSharingServiceButton = false
            view.allowsPictureInPicturePlayback = false
            view.allowsVideoFrameAnalysis = false
        }
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}
