import AppKit
import ScreenCaptureKit
import CoreMedia
import CoreImage
import Darwin

// This probe is launched as its own GUI app by LaunchServices. It captures its
// own SCStream; it is never evidence about Jump Desktop's capture process.
final class Frames: NSObject, SCStreamOutput, SCStreamDelegate {
    private let lock = NSLock()
    private var count = 0
    private var latest: CVPixelBuffer?
    private var streamError: String?
    private var animatedRect = CGRect.zero
    private var animatedChanges = 0
    private var lastAnimatedHash: UInt64?
    func configureAnimationRect(_ rect: CGRect) { lock.lock(); animatedRect = rect; lock.unlock() }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer),
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock()
        count += 1; latest = buffer
        let rect = animatedRect
        if !rect.isEmpty, CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess {
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
                let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
                var hash: UInt64 = 14695981039346656037
                let bytes = base.assumingMemoryBound(to: UInt8.self)
                for row in 0..<8 { for col in 0..<8 {
                    let x = max(0, min(width - 1, Int(rect.minX + rect.width * Double(col + 1) / 9)))
                    let y = max(0, min(height - 1, Int(rect.minY + rect.height * Double(row + 1) / 9)))
                    for channel in 0..<3 { hash = (hash ^ UInt64(bytes[y * rowBytes + x * 4 + channel])) &* 1099511628211 }
                }}
                if let previous = lastAnimatedHash, previous != hash { animatedChanges += 1 }
                lastAnimatedHash = hash
            }
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        }
        lock.unlock()
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock(); streamError = error.localizedDescription; lock.unlock()
    }
    func snapshot() -> (Int, CVPixelBuffer?, String?, Int, String) {
        lock.lock(); defer { lock.unlock() }; return (count, latest, streamError, animatedChanges, lastAnimatedHash.map { String($0, radix: 16) } ?? "")
    }
}

@MainActor
final class Probe: NSObject, NSApplicationDelegate {
    var root: URL!
    var timer: Timer?
    var window: NSWindow?
    let frames = Frames()
    var stream: SCStream?
    var displayBounds = CGRect.zero
    let context = CIContext(options: [.useSoftwareRenderer: true])
    var before: [String: Any]?
    var measureOnly: Bool { ProcessInfo.processInfo.environment["QB_MEASURE_ONLY"] == "1" }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
              ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted",
              let temp = ProcessInfo.processInfo.environment["RUNNER_TEMP"],
              CommandLine.arguments.count == 2 else { NSApp.terminate(nil); return }
        root = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
        let allowed = URL(fileURLWithPath: temp).standardizedFileURL.path + "/"
        guard root.path.hasPrefix(allowed) else { NSApp.terminate(nil); return }
        do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
        catch { NSApp.terminate(nil); return }
        write("app-process.json", ["pid": ProcessInfo.processInfo.processIdentifier,
          "parentPID": getppid(), "mode": measureOnly ? "measure-only" : "preference-cycle",
          "leg": ProcessInfo.processInfo.environment["QB_ATTRIBUTION_LEG"] ?? "default"])
        // Merely load/query class availability. No assessment assertion is created.
        var libraries: [String: Bool] = [:]
        for name in ["MenuBarClient", "MenuBarClientCore"] {
            let path = "/System/Library/PrivateFrameworks/\(name).framework/\(name)"
            libraries[name] = dlopen(path, RTLD_LAZY | RTLD_LOCAL) != nil
        }
        write("backend-availability.json", ["librariesLoaded": libraries,
          "configurationClass": NSClassFromString("MBAssessmentModeConfiguration") != nil,
          "assertionClass": NSClassFromString("MBAssessmentModeAssertion") != nil,
          "scope": "Read-only runtime availability; no configuration/assertion/activation"])

        let panel = NSWindow(contentRect: NSRect(x: 120, y: 160, width: 470, height: 180), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "QuietBar CI — own ScreenCaptureKit stream"
        let label = NSTextField(wrappingLabelWithString: "Ephemeral CI test.\nContinuous animation keeps the display stream producing complete frames.\nThis is not a Jump Desktop acceptance test.")
        label.frame = NSRect(x: 20, y: 35, width: 425, height: 100)
        panel.contentView?.addSubview(label)
        panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        window = panel
        var alternate = false
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            alternate.toggle()
            panel.backgroundColor = alternate ? NSColor(calibratedWhite: 0.92, alpha: 1) : NSColor(calibratedWhite: 0.96, alpha: 1)
        }
        Task { await run() }
    }

    func write(_ name: String, _ object: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: root.appendingPathComponent(name), options: .atomic)
        } catch { /* Missing files cause the outer runner to fail closed. */ }
    }
    func marker(_ name: String) { try? Data().write(to: root.appendingPathComponent(name), options: .atomic) }
    func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path) }
    func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    func wait(_ name: String, seconds: Int) async -> Bool {
        for _ in 0..<seconds { if exists(name) { return true }; await pause(1) }; return exists(name)
    }
    func finish(_ status: String, _ reason: String, extra: [String: Any] = [:]) async {
        var data: [String: Any] = ["schema": 1, "status": status, "reason": reason,
          "os": ProcessInfo.processInfo.operatingSystemVersionString,
          "captureSubject": "own ScreenCaptureKit SCStream; Jump Desktop not tested",
          "permissionPreflight": CGPreflightScreenCaptureAccess(),
          "before": before ?? [:]]
        for (key, value) in extra { data[key] = value }
        if let stream { try? await stream.stopCapture() }
        timer?.invalidate()
        write("capture-result.json", data); marker("capture-finished")
        NSApp.terminate(nil)
    }
    func windows() -> [[String: Any]] {
        guard let all = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return all.compactMap { item in
            guard let bounds = item[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.intersects(CGRect(x: displayBounds.minX, y: displayBounds.minY, width: displayBounds.width, height: 80)) else { return nil }
            let pid = (item[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
            let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
            let name = item[kCGWindowName as String] as? String ?? ""
            let onScreen = (item[kCGWindowIsOnscreen as String] as? Bool) ?? false
            let alpha = (item[kCGWindowAlpha as String] as? Double) ?? 1
            let layer = (item[kCGWindowLayer as String] as? Int) ?? 0
            let systemOwner = ["com.apple.controlcenter", "com.apple.systemuiserver", "com.apple.menubaragent"].contains(bundle.lowercased())
            let targetName = name.localizedCaseInsensitiveContains("AudioVideoModule") || name.localizedCaseInsensitiveContains("Audio and Video Controls")
            let target = systemOwner && targetName && onScreen && alpha > 0.05 && layer >= 20 && rect.height <= 80 && rect.width <= 400
            return ["id": item[kCGWindowNumber as String] ?? 0, "owner": item[kCGWindowOwnerName as String] ?? "", "bundleID": bundle,
                    "name": name, "layer": layer, "onScreen": onScreen, "alpha": alpha,
                    "bounds": ["x": Double(rect.minX), "y": Double(rect.minY), "width": Double(rect.width), "height": Double(rect.height)], "strictTarget": target]
        }
    }
    func purpleCount(_ image: CGImage, rect: CGRect) -> Int {
        let clipped = rect.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height)).integral
        guard !clipped.isEmpty, let crop = image.cropping(to: clipped) else { return 0 }
        let width = crop.width, height = crop.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
        var count = 0
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let red = Int(bytes[index]), green = Int(bytes[index + 1]), blue = Int(bytes[index + 2])
            if blue > 145 && red > 55 && blue > green + 40 && red >= green && blue > red + 20 { count += 1 }
        }
        return count
    }
    func snapshot(_ phase: String, baselineRects: [[String: Double]]? = nil) -> [String: Any] {
        let (count, buffer, error, changes, animatedHash) = frames.snapshot()
        let metadata = windows()
        write("\(phase)-windows.json", ["windows": metadata])
        var data: [String: Any] = ["completeFrames": count, "animatedPixelChanges": changes, "lastAnimatedRegionHashFNV1a64": animatedHash, "streamError": error ?? NSNull(), "strictVisibleTargets": metadata.filter { ($0["strictTarget"] as? Bool) == true }.count]
        guard let buffer, let image = context.createCGImage(CIImage(cvPixelBuffer: buffer), from: CIImage(cvPixelBuffer: buffer).extent) else {
            data["imageSaved"] = false; return data
        }
        // The sharing indicator itself may be excluded from an SCStream image.
        // Capture a separate native menubar screenshot and retain both sources.
        let screenURL = root.appendingPathComponent("\(phase)-system-menubar.png")
        let shot = Process()
        shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        shot.arguments = ["-x", "-R\(Int(displayBounds.minX)),\(Int(displayBounds.minY)),\(Int(displayBounds.width)),80", screenURL.path]
        shot.standardOutput = FileHandle.nullDevice; shot.standardError = FileHandle.nullDevice
        var systemImage: CGImage?
        do {
            try shot.run(); shot.waitUntilExit()
            if shot.terminationStatus == 0, let source = CGImageSourceCreateWithURL(screenURL as CFURL, nil) { systemImage = CGImageSourceCreateImageAtIndex(source, 0, nil) }
        } catch { }
        let evidenceImage = systemImage ?? image
        data["visualEvidenceSource"] = systemImage == nil ? "SCStream menubar crop" : "native screencapture menubar region"
        let scaleX = Double(evidenceImage.width) / displayBounds.width
        let scaleY = Double(evidenceImage.height) / (systemImage == nil ? displayBounds.height : 80.0)
        let top = CGRect(x: 0, y: 0, width: image.width, height: min(image.height, Int(80 * Double(image.height) / displayBounds.height)))
        if let bar = image.cropping(to: top), let png = NSBitmapImageRep(cgImage: bar).representation(using: .png, properties: [:]) {
            do { try png.write(to: root.appendingPathComponent("\(phase)-menubar.png")); data["imageSaved"] = true } catch { data["imageSaved"] = false }
        }
        let rects = baselineRects ?? metadata.filter { ($0["strictTarget"] as? Bool) == true }.compactMap { $0["bounds"] as? [String: Double] }
        data["targetRects"] = rects
        data["targetPurplePixels"] = rects.reduce(0) { total, value in
            total + purpleCount(evidenceImage, rect: CGRect(x: ((value["x"] ?? 0) - displayBounds.minX) * scaleX,
              y: ((value["y"] ?? 0) - displayBounds.minY) * scaleY,
              width: (value["width"] ?? 0) * scaleX, height: (value["height"] ?? 0) * scaleY))
        }
        return data
    }
    func measure() async {
        let started = DispatchTime.now().uptimeNanoseconds
        var samples: [[String: Any]] = []
        for second in [8, 16, 24] {
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
            await pause(max(0, Double(second) - elapsed))
            let name = "sample-\(second)s"
            var sample = snapshot(name)
            sample["elapsedSeconds"] = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
            sample["scheduledSecond"] = second
            write("\(name).json", sample); marker("\(name)-ready")
            samples.append(sample)
        }
        await finish("MEASUREMENT", "Fixed 8/16/24-second observations only; no visibility preference was changed and no hidden-target pass is inferred",
          extra: ["samples": samples, "leg": ProcessInfo.processInfo.environment["QB_ATTRIBUTION_LEG"] ?? "unspecified"])
    }
    func run() async {
        // The capture app does not write TCC or inherit Terminal permission. A
        // separate CI-only VM provisioner may attempt to grant this app access.
        // Its actual preflight remains authoritative for capture availability.
        guard CGPreflightScreenCaptureAccess() else {
            await finish("INCONCLUSIVE", "GUI capture app has no Screen Recording permission; no preference was changed"); return
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
                await finish("INCONCLUSIVE", "No capture display in runner GUI session"); return
            }
            displayBounds = CGDisplayBounds(display.displayID)
            let config = SCStreamConfiguration()
            config.width = display.width; config.height = display.height
            config.minimumFrameInterval = CMTime(value: 1, timescale: 10)
            config.pixelFormat = kCVPixelFormatType_32BGRA
            if let frame = window?.frame {
                let sx = Double(display.width) / displayBounds.width, sy = Double(display.height) / displayBounds.height
                frames.configureAnimationRect(CGRect(x: (frame.minX - displayBounds.minX + 10) * sx, y: (displayBounds.height - frame.maxY + 35) * sy, width: (frame.width - 20) * sx, height: (frame.height - 50) * sy))
            }
            config.queueDepth = 3; config.showsCursor = false; config.capturesAudio = false
            let capture = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: frames)
            stream = capture
            try capture.addStreamOutput(frames, type: .screen, sampleHandlerQueue: DispatchQueue(label: "quietbar.ci.frames"))
            try await capture.startCapture()
            if measureOnly { await measure(); return }
            await pause(8)
            let baseline = snapshot("before"); before = baseline
            write("before.json", baseline)
            guard (baseline["completeFrames"] as? Int ?? 0) >= 5,
                  (baseline["animatedPixelChanges"] as? Int ?? 0) >= 3,
                  (baseline["strictVisibleTargets"] as? Int ?? 0) >= 1,
                  (baseline["targetPurplePixels"] as? Int ?? 0) >= 15,
                  baseline["imageSaved"] as? Bool == true else {
                await finish("INCONCLUSIVE", "No verified visible purple AudioVideoModule before mutation; API acceptance or an empty menubar is not a pass"); return
            }
            marker("baseline-ready")
            guard await wait("applied", seconds: 90) else {
                await finish("INCONCLUSIVE", "Runner did not apply candidate after baseline"); return
            }
            await pause(12)
            let after = snapshot("after", baselineRects: baseline["targetRects"] as? [[String: Double]])
            write("after.json", after); marker("after-ready")
            guard await wait("restored", seconds: 90) else {
                await finish("ERROR", "Original preference restoration not confirmed", extra: ["after": after]); return
            }
            await pause(8)
            let restored = snapshot("restored", baselineRects: baseline["targetRects"] as? [[String: Double]])
            write("restored.json", restored)
            let delta = (after["completeFrames"] as? Int ?? 0) - (baseline["completeFrames"] as? Int ?? 0)
            let pixelDelta = (after["animatedPixelChanges"] as? Int ?? 0) - (baseline["animatedPixelChanges"] as? Int ?? 0)
            guard delta >= 5, pixelDelta >= 3, after["streamError"] is NSNull else {
                await finish("FAIL", "Capture stopped or ceased producing changing complete frames after a verified visible baseline and candidate application", extra: ["after": after, "restored": restored]); return
            }
            guard after["imageSaved"] as? Bool == true else {
                await finish("INCONCLUSIVE", "After image unavailable despite continued capture", extra: ["after": after, "restored": restored]); return
            }
            let beforePurple = baseline["targetPurplePixels"] as? Int ?? 0
            let afterPurple = after["targetPurplePixels"] as? Int ?? 0
            let hidden = (after["strictVisibleTargets"] as? Int ?? 1) == 0 && afterPurple * 5 < beforePurple
            let restoredFrameDelta = (restored["completeFrames"] as? Int ?? 0) - (after["completeFrames"] as? Int ?? 0)
            let restoredPixelDelta = (restored["animatedPixelChanges"] as? Int ?? 0) - (after["animatedPixelChanges"] as? Int ?? 0)
            let returned = (restored["strictVisibleTargets"] as? Int ?? 0) >= 1 && (restored["targetPurplePixels"] as? Int ?? 0) >= 15 && restoredFrameDelta >= 3 && restoredPixelDelta >= 2 && restored["streamError"] is NSNull
            await finish(hidden && returned ? "PASS_OWN_SCSTREAM" : (hidden ? "INCONCLUSIVE" : "FAIL"),
                         hidden ? (returned ? "Verified native target disappearance, continued own SCStream, and visible target return after exact preference restoration" : "Target disappeared but visible return after restore was not verified") : "Candidate did not remove the verified visible target while capture continued",
                         extra: ["after": after, "restored": restored, "continuedCompleteFrames": delta, "continuedAnimatedPixelChanges": pixelDelta, "restoredCompleteFrameDelta": restoredFrameDelta, "restoredAnimatedPixelDelta": restoredPixelDelta])
        } catch {
            await finish(exists("baseline-ready") ? "FAIL" : "INCONCLUSIVE", "ScreenCaptureKit could not start or continue: \(error.localizedDescription)")
        }
    }
}
@main
struct Main {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = Probe()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
