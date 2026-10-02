import Foundation
import AVFoundation
import AppKit

// Collector validation only. Decode the stopped movie; a console marker does
// not establish that the recorder produced playable frames.
let arguments = CommandLine.arguments
guard arguments.count == 3 else { fatalError("Supply video path and fresh output directory") }
let output = URL(fileURLWithPath: arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
let asset = AVURLAsset(url: URL(fileURLWithPath: arguments[1]))
let duration = try await asset.load(.duration)
let tracks = try await asset.loadTracks(withMediaType: .video)
guard duration.seconds.isFinite, duration.seconds > 0, let track = tracks.first else {
    fatalError("No finite duration and playable video track")
}
let size = try await track.load(.naturalSize)
let rate = try await track.load(.nominalFrameRate)
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.maximumSize = CGSize(width: 1376, height: 1032)
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
var decoded: [[String: Any]] = []
for (index, seconds) in [0.0, duration.seconds / 2, max(0, duration.seconds - 0.25)].enumerated() {
    let (frame, actual) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
    let bitmap = NSBitmapImageRep(cgImage: frame)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Frame conversion failed")
    }
    let filename = "frame-\(index + 1).png"
    try png.write(to: output.appendingPathComponent(filename))
    decoded.append(["requestedSeconds": seconds, "actualSeconds": actual.seconds,
                    "width": frame.width, "height": frame.height, "file": filename])
}
let metadata: [String: Any] = ["durationSeconds": duration.seconds, "videoTrackCount": tracks.count,
    "width": size.width, "height": size.height, "nominalFrameRate": rate, "decodedFrames": decoded]
let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
try data.write(to: output.appendingPathComponent("metadata.json"))
print(String(data: data, encoding: .utf8)!)
