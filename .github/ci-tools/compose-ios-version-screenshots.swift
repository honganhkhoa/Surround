import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

private enum ComposerError: Error, CustomStringConvertible {
    case usage
    case message(String)

    var description: String {
        switch self {
        case .usage:
            return """
            Usage:
              compose-ios-version-screenshots \
                --left IOS18.png --right IOS26.png --output COMPARISON.png \
                --left-label "iOS 18.0" --right-label "iOS 26.0" \
                --title SCENE

            Both source PNGs must have identical pixel dimensions. The output
            keeps every source pixel, adds labels above them, and is encoded as
            a non-alpha PNG.
            """
        case let .message(message):
            return message
        }
    }
}

private struct Arguments {
    let left: URL
    let right: URL
    let output: URL
    let leftLabel: String
    let rightLabel: String
    let title: String
}

private struct PNG {
    let image: CGImage
    let width: Int
    let height: Int
}

private func arguments() throws -> Arguments {
    var values = [String: String]()
    var index = 1
    while index < CommandLine.arguments.count {
        let key = CommandLine.arguments[index]
        if key == "-h" || key == "--help" {
            throw ComposerError.usage
        }
        guard key.hasPrefix("--"),
              index + 1 < CommandLine.arguments.count else {
            throw ComposerError.usage
        }
        guard values[key] == nil else {
            throw ComposerError.message("Duplicate argument: \(key)")
        }
        values[key] = CommandLine.arguments[index + 1]
        index += 2
    }

    let required = [
        "--left",
        "--right",
        "--output",
        "--left-label",
        "--right-label",
        "--title",
    ]
    for key in required where values[key] == nil {
        throw ComposerError.message("Missing required argument: \(key)")
    }

    return Arguments(
        left: URL(fileURLWithPath: values["--left"]!),
        right: URL(fileURLWithPath: values["--right"]!),
        output: URL(fileURLWithPath: values["--output"]!),
        leftLabel: values["--left-label"]!,
        rightLabel: values["--right-label"]!,
        title: values["--title"]!
    )
}

private func png(
    at url: URL,
    label: String
) throws -> PNG {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          CGImageSourceGetCount(source) == 1 else {
        throw ComposerError.message(
            "Could not decode \(label) PNG: \(url.path)"
        )
    }
    guard let type = CGImageSourceGetType(source),
          UTType(type as String)?.conforms(to: .png) == true else {
        throw ComposerError.message("\(label) is not a PNG: \(url.path)")
    }
    guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw ComposerError.message(
            "Could not decode \(label) pixels: \(url.path)"
        )
    }
    return PNG(image: image, width: image.width, height: image.height)
}

private func drawImage(
    _ image: CGImage,
    atX x: Int,
    in context: CGContext
) {
    context.draw(
        image,
        in: CGRect(
            x: x,
            y: 0,
            width: image.width,
            height: image.height
        )
    )
}

private func drawCenteredText(
    _ text: String,
    centerX: CGFloat,
    baselineY: CGFloat,
    fontSize: CGFloat,
    weight: String,
    in context: CGContext
) {
    let fontName = "SFPro-\(weight)" as CFString
    let font = CTFontCreateWithName(fontName, fontSize, nil)
    let color = CGColor(
        colorSpace: CGColorSpaceCreateDeviceRGB(),
        components: [0.12, 0.12, 0.12, 1]
    )!
    let attributed = CFAttributedStringCreate(
        nil,
        text as CFString,
        [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color,
        ] as CFDictionary
    )!
    let line = CTLineCreateWithAttributedString(attributed)
    let bounds = CTLineGetBoundsWithOptions(
        line,
        [.useGlyphPathBounds, .excludeTypographicLeading]
    )
    context.textPosition = CGPoint(
        x: centerX - (bounds.width / 2) - bounds.minX,
        y: baselineY - bounds.minY
    )
    CTLineDraw(line, context)
}

private func compose(_ arguments: Arguments) throws {
    let left = try png(at: arguments.left, label: "Left source")
    let right = try png(at: arguments.right, label: "Right source")
    guard left.width == right.width, left.height == right.height else {
        throw ComposerError.message(
            "Source dimensions differ: \(left.width)x\(left.height) versus "
                + "\(right.width)x\(right.height)."
        )
    }

    let gap = 24
    let headerHeight = 180
    let canvasWidth = (left.width * 2) + gap
    let canvasHeight = left.height + headerHeight
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: canvasWidth,
        height: canvasHeight,
        bitsPerComponent: 8,
        bytesPerRow: canvasWidth * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        throw ComposerError.message("Could not allocate the output bitmap.")
    }

    context.setFillColor(
        CGColor(
            colorSpace: colorSpace,
            components: [0.965, 0.965, 0.965, 1]
        )!
    )
    context.fill(
        CGRect(
            x: 0,
            y: 0,
            width: canvasWidth,
            height: canvasHeight
        )
    )
    drawImage(left.image, atX: 0, in: context)
    drawImage(right.image, atX: left.width + gap, in: context)

    drawCenteredText(
        arguments.title,
        centerX: CGFloat(canvasWidth) / 2,
        baselineY: CGFloat(left.height + 128),
        fontSize: 32,
        weight: "Medium",
        in: context
    )
    drawCenteredText(
        arguments.leftLabel,
        centerX: CGFloat(left.width) / 2,
        baselineY: CGFloat(left.height + 46),
        fontSize: 42,
        weight: "Semibold",
        in: context
    )
    drawCenteredText(
        arguments.rightLabel,
        centerX: CGFloat(left.width + gap) + (CGFloat(right.width) / 2),
        baselineY: CGFloat(left.height + 46),
        fontSize: 42,
        weight: "Semibold",
        in: context
    )

    guard let outputImage = context.makeImage() else {
        throw ComposerError.message("Could not finalize the output bitmap.")
    }
    let outputDirectory = arguments.output.deletingLastPathComponent()
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(
        atPath: outputDirectory.path,
        isDirectory: &isDirectory
    ), isDirectory.boolValue else {
        throw ComposerError.message(
            "Output directory does not exist: \(outputDirectory.path)"
        )
    }
    guard let destination = CGImageDestinationCreateWithURL(
        arguments.output as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw ComposerError.message("Could not create the output PNG.")
    }
    CGImageDestinationAddImage(
        destination,
        outputImage,
        [
            kCGImagePropertyHasAlpha: false,
            kCGImagePropertyOrientation: 1,
        ] as CFDictionary
    )
    guard CGImageDestinationFinalize(destination) else {
        throw ComposerError.message("Could not encode the output PNG.")
    }
}

do {
    try compose(try arguments())
} catch ComposerError.usage {
    fputs("\(ComposerError.usage)\n", stderr)
    exit(64)
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
