import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct DecodedImage: Equatable, Sendable {
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let hasAlpha: Bool
    public let orientation: Int
}

public enum ImageValidation {
    public static func decodePNG(_ data: Data, context: String) throws -> DecodedImage {
        let options = [kCGImageSourceShouldCache: true] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            throw ReleaseToolError.validation("Could not decode PNG data: \(context)")
        }
        guard CGImageSourceGetStatus(source) == .statusComplete else {
            throw ReleaseToolError.validation("PNG data is incomplete or corrupt: \(context)")
        }
        guard CGImageSourceGetType(source) as String? == UTType.png.identifier else {
            throw ReleaseToolError.validation("Image is not a PNG: \(context)")
        }
        guard CGImageSourceGetCount(source) == 1 else {
            throw ReleaseToolError.validation("PNG must contain exactly one image frame: \(context)")
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, options) else {
            throw ReleaseToolError.validation("Could not fully decode PNG pixels: \(context)")
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw ReleaseToolError.validation("Could not read PNG metadata: \(context)")
        }
        let rootOrientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let tiffOrientation = (tiff?[kCGImagePropertyTIFFOrientation] as? NSNumber)?.intValue
        let exif = properties[kCGImagePropertyExifDictionary] as? [String: Any]
        let exifOrientation = (exif?["Orientation"] as? NSNumber)?.intValue
        let orientations = [rootOrientation, tiffOrientation, exifOrientation].compactMap { $0 }
        guard orientations.allSatisfy({ $0 == 1 }) else {
            throw ReleaseToolError.validation(
                "PNG orientation metadata must be neutral (1), found \(orientations): \(context)"
            )
        }
        let hasAlpha: Bool
        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            hasAlpha = true
        case .none, .noneSkipFirst, .noneSkipLast:
            hasAlpha = false
        @unknown default:
            hasAlpha = true
        }
        return DecodedImage(
            pixelWidth: image.width,
            pixelHeight: image.height,
            hasAlpha: hasAlpha,
            orientation: orientations.first ?? 1
        )
    }

    @discardableResult
    public static func validateScreenshot(
        _ data: Data,
        pixelWidth: Int,
        pixelHeight: Int,
        context: String
    ) throws -> DecodedImage {
        let decoded = try decodePNG(data, context: context)
        guard decoded.pixelWidth == pixelWidth, decoded.pixelHeight == pixelHeight else {
            throw ReleaseToolError.validation(
                "Screenshot has \(decoded.pixelWidth)x\(decoded.pixelHeight) pixels; expected \(pixelWidth)x\(pixelHeight): \(context)"
            )
        }
        guard !decoded.hasAlpha else {
            throw ReleaseToolError.validation("Screenshot contains an alpha channel: \(context)")
        }
        return decoded
    }

    /// Returns a replayable PNG without an alpha channel when the input's
    /// alpha channel is present but every pixel is fully opaque. Any genuine
    /// transparency remains a hard validation failure.
    public static func removingOpaqueAlphaChannel(
        from data: Data,
        context: String
    ) throws -> Data {
        let decoded = try decodePNG(data, context: context)
        guard decoded.hasAlpha else { return data }

        let options = [kCGImageSourceShouldCache: true] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let image = CGImageSourceCreateImageAtIndex(source, 0, options) else {
            throw ReleaseToolError.validation("Could not decode PNG pixels: \(context)")
        }
        let (pixelCount, pixelOverflow) = image.width.multipliedReportingOverflow(by: image.height)
        let (byteCount, byteOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
        guard !pixelOverflow, !byteOverflow, byteCount > 0 else {
            throw ReleaseToolError.validation("PNG dimensions are too large: \(context)")
        }

        let colorSpace: CGColorSpace
        if let sourceColorSpace = image.colorSpace, sourceColorSpace.model == .rgb {
            colorSpace = sourceColorSpace
        } else {
            colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        }
        let bytesPerRow = image.width * 4
        let rgbaBitmapInfo = CGBitmapInfo(rawValue:
            CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue
        )
        var pixels = [UInt8](repeating: 0, count: byteCount)
        try pixels.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress,
                  let bitmap = CGContext(
                    data: baseAddress,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: rgbaBitmapInfo.rawValue
                  ) else {
                throw ReleaseToolError.validation(
                    "Could not inspect PNG alpha pixels: \(context)"
                )
            }
            bitmap.interpolationQuality = .none
            bitmap.draw(
                image,
                in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
            )
        }
        guard stride(from: 3, to: pixels.count, by: 4).allSatisfy({ pixels[$0] == 255 }) else {
            throw ReleaseToolError.validation(
                "PNG contains transparent pixels and cannot be replayed safely: \(context)"
            )
        }

        let providerData = Data(pixels)
        guard let provider = CGDataProvider(data: providerData as CFData) else {
            throw ReleaseToolError.validation("Could not prepare opaque PNG pixels: \(context)")
        }
        let opaqueBitmapInfo = CGBitmapInfo(rawValue:
            CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.noneSkipLast.rawValue
        )
        guard let opaqueImage = CGImage(
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: opaqueBitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: image.renderingIntent
        ) else {
            throw ReleaseToolError.validation("Could not create alpha-free PNG: \(context)")
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ReleaseToolError.validation("Could not create PNG destination: \(context)")
        }
        CGImageDestinationAddImage(destination, opaqueImage, [
            kCGImagePropertyOrientation: 1,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ReleaseToolError.validation("Could not encode alpha-free PNG: \(context)")
        }
        let normalized = output as Data
        let normalizedImage = try decodePNG(normalized, context: "normalized \(context)")
        guard normalizedImage.pixelWidth == decoded.pixelWidth,
              normalizedImage.pixelHeight == decoded.pixelHeight,
              normalizedImage.hasAlpha == false,
              normalizedImage.orientation == 1 else {
            throw ReleaseToolError.validation(
                "Alpha-free PNG failed read-back validation: \(context)"
            )
        }
        return normalized
    }
}
