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

    private func handlePlayPause(isPlaying: Bool, result: @escaping FlutterResult) {
        let target: UInt32 = isPlaying ? 1 : 0 // 1=pause, 0=play

        // Primary: MRMediaRemoteSendCommand targets the active audio session
        if let send = mediaRemoteSendCommand {
            send(target, nil)
        }

        // Secondary: MPRemoteCommandCenter as fallback
        let center = MPRemoteCommandCenter.shared()
        let cmd = isPlaying ? center.pauseCommand : center.playCommand
        let sel = NSSelectorFromString("sendRemoteCommandEvent:")
        if cmd.responds(to: sel),
           let cls = NSClassFromString("MPRemoteCommandEvent") as? NSObject.Type {
            let event = cls.init()
            _ = cmd.perform(sel, with: event)
        }

        result(nil)
    }

    private func handleNext(result: @escaping FlutterResult) {
        if let send = mediaRemoteSendCommand { send(4, nil) }
        let sel = NSSelectorFromString("sendRemoteCommandEvent:")
        let cmd = MPRemoteCommandCenter.shared().nextTrackCommand
        if cmd.responds(to: sel),
           let cls = NSClassFromString("MPRemoteCommandEvent") as? NSObject.Type {
            let event = cls.init()
            _ = cmd.perform(sel, with: event)
        }
        result(nil)
    }

    private func handlePrevious(result: @escaping FlutterResult) {
        if let send = mediaRemoteSendCommand { send(5, nil) }
        let sel = NSSelectorFromString("sendRemoteCommandEvent:")
        let cmd = MPRemoteCommandCenter.shared().previousTrackCommand
        if cmd.responds(to: sel),
           let cls = NSClassFromString("MPRemoteCommandEvent") as? NSObject.Type {
            let event = cls.init()
            _ = cmd.perform(sel, with: event)
        }
        result(nil)
    }

    // ── Now Playing Metadata ──────────────────────────────────────────────

    private func handleNowPlaying(result: @escaping FlutterResult) {
        guard let getInfo = mediaRemoteGetNowPlaying else {
            result(["title": "Unknown", "artist": "Unknown", "artwork": ""])
            return
        }

        getInfo(.main) { dict in
            guard let ns = dict as NSDictionary?, ns.count > 0 else {
                // No data from MediaRemote — return Unknown (don't use
                // MPMusicPlayerController which returns stale Apple Music data)
                result(["title": "Unknown", "artist": "Unknown", "artwork": ""])
                return
            }

            let allKeys = ns.allKeys.compactMap { $0 as? String }

            // Extract title — try known keys, then search dynamically
            var title: String? = ns["kMRMediaRemoteNowPlayingInfoTitle"] as? String
                              ?? ns["__kMRMediaRemoteNowPlayingInfoTitle"] as? String
            if title == nil {
                for k in allKeys {
                    let kl = k.lowercased()
                    if kl.contains("title") || kl.contains("song") || kl.contains("track") {
                        title = ns[k] as? String
                        if title != nil { break }
                    }
                }
            }

            // Extract artist
            var artist: String? = ns["kMRMediaRemoteNowPlayingInfoArtist"] as? String
                               ?? ns["__kMRMediaRemoteNowPlayingInfoArtist"] as? String
            if artist == nil {
                for k in allKeys {
                    if k.lowercased().contains("artist") {
                        artist = ns[k] as? String
                        if artist != nil { break }
                    }
                }
            }

            // Extract artwork as base64
            var b64Artwork = ""
            if let data = (
                ns["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data ??
                ns["__kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
            ) {
                b64Artwork = data.base64EncodedString()
            }
            // Artwork might also come as a dict with "data" key
            if b64Artwork.isEmpty {
                for k in allKeys {
                    if k.lowercased().contains("artwork") || k.lowercased().contains("album") {
                        if let imgDict = ns[k] as? [String: Any],
                           let imgData = imgDict["data"] as? Data {
                            b64Artwork = imgData.base64EncodedString()
                            break
                        }
                    }
                }
            }

            result([
                "title":   title   ?? "Unknown",
                "artist":  artist  ?? "Unknown",
                "artwork": b64Artwork,
            ])
        }
    }
}
