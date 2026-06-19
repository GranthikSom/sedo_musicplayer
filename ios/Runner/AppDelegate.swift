import UIKit
import Flutter
import MediaPlayer

private let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)

@main
@objc class AppDelegate: FlutterAppDelegate {

    private let channelName = "music/bridge"

    // ── Private MediaRemote API (loaded via dlsym) ──────────────────────────

    private typealias MRMediaRemoteSendCommandFn =
        @convention(c) (Int, CFDictionary?) -> Void
    private typealias MRMediaRemoteSendCommandWithResultFn =
        @convention(c) (Int, CFDictionary?, (@convention(block) (UInt32) -> Void)?) -> Void
    private typealias MRMediaRemoteGetNowPlayingInfoFn =
        @convention(c) (DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void
    private typealias MRMediaRemoteGetNowPlayingApplicationDisplayIDFn =
        @convention(c) () -> CFString?

    private struct MediaRemote {
        let send: MRMediaRemoteSendCommandFn
        let sendWithResult: MRMediaRemoteSendCommandWithResultFn
        let getNowPlaying: MRMediaRemoteGetNowPlayingInfoFn
        let getAppDisplayID: MRMediaRemoteGetNowPlayingApplicationDisplayIDFn
    }

    private lazy var mr: MediaRemote? = {
        // Try RTLD_DEFAULT first — MediaRemote is loaded into every process
        let find: (String) -> UnsafeMutableRawPointer? = { name in
            if let s = dlsym(RTLD_DEFAULT, name) { return s }
            let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
            if let h = dlopen(path, RTLD_NOW | RTLD_NOLOAD), let s = dlsym(h, name) { return s }
            if let h = dlopen(path, RTLD_NOW),           let s = dlsym(h, name) { return s }
            return nil
        }
        guard
            let s = find("MRMediaRemoteSendCommand"),
            let r = find("MRMediaRemoteSendCommandWithResult"),
            let g = find("MRMediaRemoteGetNowPlayingInfo"),
            let a = find("MRMediaRemoteGetNowPlayingApplicationDisplayID")
        else {
            NSLog("[Sedo] FAILED to load MediaRemote symbols:")
            if dlsym(RTLD_DEFAULT, "MRMediaRemoteSendCommand") == nil { NSLog("[Sedo]   MRMediaRemoteSendCommand — MISSING") }
            if dlsym(RTLD_DEFAULT, "MRMediaRemoteSendCommandWithResult") == nil { NSLog("[Sedo]   MRMediaRemoteSendCommandWithResult — MISSING") }
            if dlsym(RTLD_DEFAULT, "MRMediaRemoteGetNowPlayingInfo") == nil { NSLog("[Sedo]   MRMediaRemoteGetNowPlayingInfo — MISSING") }
            if dlsym(RTLD_DEFAULT, "MRMediaRemoteGetNowPlayingApplicationDisplayID") == nil { NSLog("[Sedo]   MRMediaRemoteGetNowPlayingApplicationDisplayID — MISSING") }
            return nil
        }
        NSLog("[Sedo] MediaRemote APIs loaded via RTLD_DEFAULT")
        return MediaRemote(
            send:           unsafeBitCast(s, to: MRMediaRemoteSendCommandFn.self),
            sendWithResult: unsafeBitCast(r, to: MRMediaRemoteSendCommandWithResultFn.self),
            getNowPlaying:  unsafeBitCast(g, to: MRMediaRemoteGetNowPlayingInfoFn.self),
            getAppDisplayID: unsafeBitCast(a, to: MRMediaRemoteGetNowPlayingApplicationDisplayIDFn.self)
        )
    }()

    // ── App Launch ──────────────────────────────────────────────────────────

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        guard let controller = window?.rootViewController as? FlutterViewController else {
            fatalError("[Sedo] rootViewController is not FlutterViewController")
        }

        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: controller.binaryMessenger
        )

        channel.setMethodCallHandler { [weak self] (call, result) in
            guard let self = self else { return }
            switch call.method {
            case "playPause":  self.handlePlayPause(result: result)
            case "next":       self.handleNext(result: result)
            case "previous":   self.handlePrevious(result: result)
            case "nowPlaying": self.handleNowPlaying(result: result)
            default:           result(FlutterMethodNotImplemented)
            }
        }

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // ── Playback Controls ───────────────────────────────────────────────────

    private func handlePlayPause(result: @escaping FlutterResult) {
        guard let mr = mr else {
            NSLog("[Sedo] playPause — mr is nil, using fallback")
            fallbackPlayPause()
            result(nil)
            return
        }
        // Send toggle + play + pause (+ sendWithResult for status)
        mr.sendWithResult(2, nil) { s in
            NSLog("[Sedo] togglePlayPause → status=\(s)")
        }
        mr.send(0, nil)
        mr.send(1, nil)
        result(nil)
    }

    private func handleNext(result: @escaping FlutterResult) {
        guard let mr = mr else { NSLog("[Sedo] next — mr nil"); result(nil); return }
        mr.sendWithResult(4, nil) { s in NSLog("[Sedo] nextTrack → status=\(s)") }
        result(nil)
    }

    private func handlePrevious(result: @escaping FlutterResult) {
        guard let mr = mr else { NSLog("[Sedo] prev — mr nil"); result(nil); return }
        mr.sendWithResult(5, nil) { s in NSLog("[Sedo] prevTrack → status=\(s)") }
        result(nil)
    }

    private func fallbackPlayPause() {
        let p = MPMusicPlayerController.systemMusicPlayer
        if #available(iOS 16, *) {
            switch p.playbackState {
            case .playing: p.pause()
            default:       p.play()
            }
        }
    }

    // ── Now Playing Metadata ───────────────────────────────────────────────

    private func handleNowPlaying(result: @escaping FlutterResult) {
        guard let mr = mr else {
            NSLog("[Sedo] nowPlaying — mr is nil, using fallback")
            fallbackNP(result: result)
            return
        }

        // Log which app the system thinks is the now-playing app
        let appID = mr.getAppDisplayID()
        NSLog("[Sedo] NowPlaying app: \(appID ?? "nil" as CFString)")

        // Fetch system-wide now playing info via private API
        mr.getNowPlaying(DispatchQueue.main) { [weak self] cf in
            guard let self = self else { return }

            guard let dict = cf as? [String: Any] else {
                NSLog("[Sedo] MRMediaRemoteGetNowPlayingInfo returned nil/empty")
                self.fallbackNP(result: result)
                return
            }

            let nd = dict as NSDictionary
            if !self.didLogNPKeys {
                NSLog("[Sedo] --- NowPlaying dictionary has \(nd.allKeys.count) keys ---")
                for k in nd.allKeys {
                    NSLog("[Sedo]   NP key: \(k) = \(nd[k] ?? "nil")")
                }
                self.didLogNPKeys = true
            }

            let title  = self.scanNP(nd, ["title","Title","kMRMediaRemoteNowPlayingInfoTitle"])
                      ?? self.str(dict[MPMediaItemPropertyTitle]) ?? "Unknown"
            let artist = self.scanNP(nd, ["artist","Artist","kMRMediaRemoteNowPlayingInfoArtist"])
                      ?? self.str(dict[MPMediaItemPropertyArtist]) ?? "Unknown"

            NSLog("[Sedo] NP result: '\(title)' – '\(artist)'")
            result(["title": title, "artist": artist])
        }
    }

    private var didLogNPKeys = false

    private func scanNP(_ d: NSDictionary, _ keys: [String]) -> String? {
        for k in keys {
            if let v = d[k] as? String, !v.isEmpty { return v }
        }
        for k in d.allKeys {
            guard let ks = k as? String else { continue }
            for s in keys {
                if ks.lowercased().contains(s.lowercased()) {
                    return d[k] as? String
                }
            }
        }
        return nil
    }

    private func str(_ v: Any?) -> String? {
        (v as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private func fallbackNP(result: @escaping FlutterResult) {
        if let item = MPMusicPlayerController.systemMusicPlayer.nowPlayingItem {
            result(["title": item.title ?? "Unknown", "artist": item.artist ?? "Unknown"])
        } else {
            let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
            result([
                "title":  info?[MPMediaItemPropertyTitle]  as? String ?? "Unknown",
                "artist": info?[MPMediaItemPropertyArtist] as? String ?? "Unknown",
            ])
        }
    }
}
