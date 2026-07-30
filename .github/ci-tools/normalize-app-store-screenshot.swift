import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private enum ScreenshotError: Error, CustomStringConvertible {
    case usage
    case message(String)

    var description: String {
        switch self {
        case .usage:
            return """
            Usage:
              normalize-app-store-screenshot INPUT.png OUTPUT.png
              normalize-app-store-screenshot --validate-neutral FILE.png

            The normalizing form bakes EXIF/TIFF orientation into the pixel
            raster, writes a PNG with orientation 1, and updates all stored
            pixel dimensions. The validation form verifies those invariants.
            """
        case let .message(message):
            return message
        }
    }
}

private struct ImageProperties {
    let width: Int
    let height: Int
    let orientation: CGImagePropertyOrientation
    let dictionary: [CFString: Any]
}

private func integer(_ value: Any?) -> Int? {
    if let number = value as? NSNumber {
        return number.intValue
    }
    if let value = value as? Int {
        return value
    }
    if let value = value as? String {
        return Int(value)
    }
    return nil
}

private func dictionary(
    _ value: Any?
) -> [CFString: Any] {
    value as? [CFString: Any] ?? [:]
}

private func imageProperties(
    from source: CGImageSource,
    label: String
) throws -> ImageProperties {
    guard CGImageSourceGetCount(source) == 1 else {
        throw ScreenshotError.message(
            "\(label) must contain exactly one image."
        )
    }

    guard
        let properties = CGImageSourceCopyPropertiesAtIndex(
            source,
            0,
            nil
        ) as? [CFString: Any],
        let width = integer(properties[kCGImagePropertyPixelWidth]),
        let height = integer(properties[kCGImagePropertyPixelHeight])
    else {
        throw ScreenshotError.message(
            "Could not read pixel dimensions from \(label)."
        )
    }

    let rawOrientation =
        integer(properties[kCGImagePropertyOrientation]) ?? 1
    guard
        let orientation = CGImagePropertyOrientation(
            rawValue: UInt32(rawOrientation)
        )
    else {
        throw ScreenshotError.message(
            "\(label) has unsupported orientation \(rawOrientation)."
        )
    }

    return ImageProperties(
        width: width,
        height: height,
        orientation: orientation,
        dictionary: properties
    )
}

private func transformedDimensions(
    width: Int,
    height: Int,
    orientation: CGImagePropertyOrientation
) -> (width: Int, height: Int) {
    switch orientation {
    case .leftMirrored, .right, .rightMirrored, .left:
        return (height, width)
    default:
        return (width, height)
    }
}

private func normalizedImage(
    source: CGImageSource,
    properties: ImageProperties,
    label: String
) throws -> CGImage {
    let expectedDimensions = transformedDimensions(
        width: properties.width,
        height: properties.height,
        orientation: properties.orientation
    )
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize:
            max(properties.width, properties.height),
        kCGImageSourceShouldCacheImmediately: true,
    ]
    guard
        let outputImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        )
    else {
        throw ScreenshotError.message(
            "Could not create a normalized raster for \(label)."
        )
    }
    guard
        outputImage.width == expectedDimensions.width,
        outputImage.height == expectedDimensions.height
    else {
        throw ScreenshotError.message(
            "Image I/O produced \(outputImage.width)x"
                + "\(outputImage.height) for \(label), expected "
                + "\(expectedDimensions.width)x"
                + "\(expectedDimensions.height)."
        )
    }
    return outputImage
}

private func neutralMetadata(
    source: [CFString: Any],
    width: Int,
    height: Int
) -> [CFString: Any] {
    var output = source
    output[kCGImagePropertyPixelWidth] = width
    output[kCGImagePropertyPixelHeight] = height
    output[kCGImagePropertyHasAlpha] = false
    output[kCGImagePropertyOrientation] = 1

    var tiff = dictionary(output[kCGImagePropertyTIFFDictionary])
    tiff[kCGImagePropertyTIFFOrientation] = 1
    output[kCGImagePropertyTIFFDictionary] = tiff

    var exif = dictionary(output[kCGImagePropertyExifDictionary])
    exif[kCGImagePropertyExifPixelXDimension] = width
    exif[kCGImagePropertyExifPixelYDimension] = height
    output[kCGImagePropertyExifDictionary] = exif

    return output
}

private func containsAlpha(_ image: CGImage) -> Bool {
    switch image.alphaInfo {
    case .first, .last, .premultipliedFirst, .premultipliedLast,
         .alphaOnly:
        return true
    case .none, .noneSkipFirst, .noneSkipLast:
        return false
    @unknown default:
        return true
    }
}

@discardableResult
private func validateNeutral(
    source: CGImageSource,
    label: String
) throws -> ImageProperties {
    guard
        let sourceType = CGImageSourceGetType(source),
        UTType(sourceType as String)?.conforms(to: .png) == true
    else {
        throw ScreenshotError.message("\(label) is not a PNG.")
    }

    let properties = try imageProperties(from: source, label: label)
    guard
        integer(
            properties.dictionary[kCGImagePropertyOrientation]
        ) == 1
    else {
        throw ScreenshotError.message(
            "\(label) has root orientation "
                + "\(properties.orientation.rawValue), expected 1."
        )
    }

    let tiff = dictionary(
        properties.dictionary[kCGImagePropertyTIFFDictionary]
    )
    guard integer(tiff[kCGImagePropertyTIFFOrientation]) == 1 else {
        throw ScreenshotError.message(
            "\(label) does not have TIFF orientation 1."
        )
    }
    let exif = dictionary(
        properties.dictionary[kCGImagePropertyExifDictionary]
    )
    guard
        integer(exif[kCGImagePropertyExifPixelXDimension])
            == properties.width,
        integer(exif[kCGImagePropertyExifPixelYDimension])
            == properties.height
    else {
        throw ScreenshotError.message(
            "\(label) has stale EXIF pixel dimensions."
        )
    }

    guard
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw ScreenshotError.message(
            "Could not decode \(label) for validation."
        )
    }
    guard !containsAlpha(image) else {
        throw ScreenshotError.message(
            "\(label) has an alpha channel."
        )
    }

    return properties
}

private func normalize(input: URL, output: URL) throws {
    guard
        let source = CGImageSourceCreateWithURL(
            input as CFURL,
            nil
        )
    else {
        throw ScreenshotError.message(
            "Could not open \(input.path)."
        )
    }

    let outputDirectory = output.deletingLastPathComponent()
    var isDirectory: ObjCBool = false
    guard
        FileManager.default.fileExists(
            atPath: outputDirectory.path,
            isDirectory: &isDirectory
        ),
        isDirectory.boolValue
    else {
        throw ScreenshotError.message(
            "Output directory does not exist: \(outputDirectory.path)"
        )
    }

    let properties = try imageProperties(
        from: source,
        label: input.path
    )
    let outputImage = try normalizedImage(
        source: source,
        properties: properties,
        label: input.path
    )
    let outputProperties = neutralMetadata(
        source: properties.dictionary,
        width: outputImage.width,
        height: outputImage.height
    )

    let encodedData = NSMutableData()
    guard
        let destination = CGImageDestinationCreateWithData(
            encodedData,
            UTType.png.identifier as CFString,
            1,
            nil
        )
    else {
        throw ScreenshotError.message(
            "Could not create a PNG destination for \(output.path)."
        )
    }

    CGImageDestinationAddImage(
        destination,
        outputImage,
        outputProperties as CFDictionary
    )
    guard CGImageDestinationFinalize(destination) else {
        throw ScreenshotError.message(
            "Could not encode \(output.path)."
        )
    }

    guard
        let encodedSource = CGImageSourceCreateWithData(
            encodedData,
            nil
        )
    else {
        throw ScreenshotError.message(
            "Could not reopen encoded data for \(output.path)."
        )
    }
    let validatedProperties = try validateNeutral(
        source: encodedSource,
        label: output.path
    )

    try (encodedData as Data).write(to: output, options: .atomic)
    print(
        "\(input.path) -> \(output.path): "
            + "\(properties.width)x\(properties.height) "
            + "orientation \(properties.orientation.rawValue) -> "
            + "\(validatedProperties.width)x"
            + "\(validatedProperties.height) orientation 1"
    )
}

private func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.count == 2, arguments[0] == "--validate-neutral" {
        let input = URL(fileURLWithPath: arguments[1])
        guard
            let source = CGImageSourceCreateWithURL(input as CFURL, nil)
        else {
            throw ScreenshotError.message(
                "Could not open \(input.path)."
            )
        }
        let properties = try validateNeutral(
            source: source,
            label: input.path
        )
        print(
            "\(input.path): \(properties.width)x\(properties.height), "
                + "PNG, no alpha, root/TIFF orientation 1, "
                + "EXIF dimensions current"
        )
        return
    }

    guard arguments.count == 2 else {
        throw ScreenshotError.usage
    }
    try normalize(
        input: URL(fileURLWithPath: arguments[0]),
        output: URL(fileURLWithPath: arguments[1])
    )
}

do {
    try run()
} catch let error as ScreenshotError {
    FileHandle.standardError.write(
        Data("error: \(error.description)\n".utf8)
    )
    switch error {
    case .usage:
        exit(64)
    case .message:
        exit(1)
    }
} catch {
    FileHandle.standardError.write(
        Data("error: \(error.localizedDescription)\n".utf8)
    )
    exit(1)
}
