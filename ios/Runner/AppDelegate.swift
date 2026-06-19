import UIKit
import Flutter
import MediaPlayer

// ── MediaRemote private API ──────────────────────────────────────────────

private let mediaRemoteHandle: UnsafeMutableRawPointer? = {
    dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
}()

private typealias MRGetNowPlayingFunc = @convention(c) (DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void
private let mediaRemoteGetNowPlaying: MRGetNowPlayingFunc? = {
    guard let h = mediaRemoteHandle, let s = dlsym(h, "MRMediaRemoteGetNowPlayingInfo") else { return nil }
    return unsafeBitCast(s, to: MRGetNowPlayingFunc.self)
}()

private typealias MRSendCommandFunc = @convention(c) (UInt32, CFDictionary?) -> Void
private let mediaRemoteSendCommand: MRSendCommandFunc? = {
    guard let h = mediaRemoteHandle, let s = dlsym(h, "MRMediaRemoteSendCommand") else { return nil }
    return unsafeBitCast(s, to: MRSendCommandFunc.self)
}()

// ─────────────────────────────────────────────────────────────────────────

@main
@objc class AppDelegate: FlutterAppDelegate {

    private let channelName = "music/bridge"

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        guard let controller = window?.rootViewController as? FlutterViewController else {
            fatalError("[SedoBridge] rootViewController is not a FlutterViewController")
        }

        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: controller.binaryMessenger
        )

        channel.setMethodCallHandler { [weak self] (call, result) in
            guard let self = self else { return }
            switch call.method {
            case "playPause":
                let isPlaying = (call.arguments as? Bool) ?? false
                self.handlePlayPause(isPlaying: isPlaying, result: result)
            case "next":        self.handleNext(result: result)
            case "previous":    self.handlePrevious(result: result)
            case "nowPlaying":  self.handleNowPlaying(result: result)
            default:            result(FlutterMethodNotImplemented)
            }
        }

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // ── Playback Controls ──────────────────────────────────────────────────

    /// Sends play or pause based on the current UI state from Dart.
    /// [isPlaying] tells us whether the system APPEARS to be playing,
    /// so we send pause (1) if playing, play (0) if paused.
    private func handlePlayPause(isPlaying: Bool, result: @escaping FlutterResult) {
        if let send = mediaRemoteSendCommand {
            send(isPlaying ? 1 : 0, nil) // 1=pause, 0=play
            result(nil)
        } else {
            fallbackTogglePlayPause(result: result)
        }
    }

    private func handleNext(result: @escaping FlutterResult) {
        if let send = mediaRemoteSendCommand {
            send(4, nil)
        } else {
            fallbackSendCommand(4)
        }
        result(nil)
    }

    private func handlePrevious(result: @escaping FlutterResult) {
        if let send = mediaRemoteSendCommand {
            send(5, nil)
        } else {
            fallbackSendCommand(5)
        }
        result(nil)
    }

    // ── Now Playing Metadata ──────────────────────────────────────────────

    private func handleNowPlaying(result: @escaping FlutterResult) {
        guard let getInfo = mediaRemoteGetNowPlaying else {
            completeNowPlaying(result: result, title: "Unknown", artist: "Unknown")
            return
        }

        // Async: callback fires on .main when data is ready.
        // No semaphore needed — Flutter's result can be called later.
        getInfo(.main) { dict in
            let ns = dict as NSDictionary?
            let mrTitle  = ns?["kMRMediaRemoteNowPlayingInfoTitle"]  as? String
                        ?? ns?["__kMRMediaRemoteNowPlayingInfoTitle"] as? String
                        ?? "Unknown"
            let mrArtist = ns?["kMRMediaRemoteNowPlayingInfoArtist"]  as? String
                        ?? ns?["__kMRMediaRemoteNowPlayingInfoArtist"] as? String
                        ?? "Unknown"

            // If MediaRemote returned real data, use it directly
            if mrTitle != "Unknown" || mrArtist != "Unknown" {
                result(["title": mrTitle, "artist": mrArtist])
                return
            }

            // Fallback chaining
            self.completeNowPlaying(result: result, title: mrTitle, artist: mrArtist)
        }
    }

    /// Chains fallbacks: MPMusicPlayerController → MPNowPlayingInfoCenter
    private func completeNowPlaying(result: FlutterResult, title: String, artist: String) {
        var t = title, a = artist

        // MPMusicPlayerController (Apple Music)
        if t == "Unknown" || a == "Unknown" {
            let player = MPMusicPlayerController.systemMusicPlayer
            if let item = player.nowPlayingItem {
                if t == "Unknown" { t = item.title ?? "Unknown" }
                if a == "Unknown" { a = item.artist ?? "Unknown" }
            }
        }

        // MPNowPlayingInfoCenter (this app only — rarely useful)
        if t == "Unknown" || a == "Unknown" {
            let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
            if t == "Unknown" { t = info?[MPMediaItemPropertyTitle] as? String ?? "Unknown" }
            if a == "Unknown" { a = info?[MPMediaItemPropertyArtist] as? String ?? "Unknown" }
        }

        result(["title": t, "artist": a])
    }

    // ── Fallbacks ─────────────────────────────────────────────────────────

    private func fallbackTogglePlayPause(result: FlutterResult) {
        let sel = NSSelectorFromString("sendRemoteCommandEvent:")
        let center = MPRemoteCommandCenter.shared()
        if center.playCommand.responds(to: sel),
           let cls = NSClassFromString("MPRemoteCommandEvent") as? NSObject.Type {
            let event = cls.init()
            _ = center.playCommand.perform(sel, with: event)
        } else {
            MPMusicPlayerController.systemMusicPlayer.play()
        }
        result(nil)
    }

    private func fallbackSendCommand(_ cmd: UInt32) {
        if cmd == 4 {
            MPMusicPlayerController.systemMusicPlayer.skipToNextItem()
        } else {
            MPMusicPlayerController.systemMusicPlayer.skipToPreviousItem()
        }
    }
}
