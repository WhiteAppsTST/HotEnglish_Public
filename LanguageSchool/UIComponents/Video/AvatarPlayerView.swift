import AVFoundation
import SwiftUI
import UIKit

/// Silent-видео плеер для аватара учительницы. Оборачивает `AVPlayerLayer`
/// через `UIViewRepresentable`, без стандартных playback-контролов.
///
/// Использование:
/// ```swift
/// @State private var player = AvatarPlayer()
/// var body: some View {
///     AvatarPlayerView(player: player.videoPlayer)
///         .aspectRatio(9/16, contentMode: .fill)
///         .onAppear {
///             if let url = teacher.lessonVideo(.idle) {
///                 player.setBase(video: url)
///             }
///         }
/// }
/// ```
struct AvatarPlayerView: UIViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        if uiView.playerLayer.videoGravity != videoGravity {
            uiView.playerLayer.videoGravity = videoGravity
        }
    }
}

/// UIView с `AVPlayerLayer` в качестве back-layer. Позволяет отрисовать
/// видео без AVKit-UI (никаких кнопок, скраббера и т.п.).
final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
