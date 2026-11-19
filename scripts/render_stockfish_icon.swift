import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func makeIcon(side: Int) -> Data {
    let bounds = CGRect(x: 0, y: 0, width: side, height: side)
    let context = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    let background = CGColor(red: 0.055, green: 0.11, blue: 0.096, alpha: 1)
    context.setFillColor(background)
    context.fill(bounds)
    let scale = CGFloat(side) / 1024
    context.scaleBy(x: scale, y: scale)
    context.setStrokeColor(CGColor(red: 0.51, green: 0.67, blue: 0.49, alpha: 0.55))
    context.setLineWidth(19)
    context.stroke(CGRect(x: 170, y: 170, width: 684, height: 684))

    let knight = CGMutablePath()
    knight.move(to: CGPoint(x: 283, y: 285))
    knight.addLine(to: CGPoint(x: 748, y: 285))
    knight.addLine(to: CGPoint(x: 748, y: 358))
    knight.addLine(to: CGPoint(x: 687, y: 391))
    knight.addQuadCurve(to: CGPoint(x: 715, y: 565), control: CGPoint(x: 733, y: 479))
    knight.addQuadCurve(to: CGPoint(x: 587, y: 725), control: CGPoint(x: 689, y: 679))
    knight.addLine(to: CGPoint(x: 524, y: 805))
    knight.addLine(to: CGPoint(x: 493, y: 735))
    knight.addLine(to: CGPoint(x: 426, y: 714))
    knight.addLine(to: CGPoint(x: 284, y: 541))
    knight.addLine(to: CGPoint(x: 347, y: 465))
    knight.addLine(to: CGPoint(x: 491, y: 537))
    knight.addQuadCurve(to: CGPoint(x: 343, y: 393), control: CGPoint(x: 485, y: 459))
    knight.addLine(to: CGPoint(x: 283, y: 360))
    knight.closeSubpath()
    context.addPath(knight)
    context.setFillColor(CGColor(red: 0.78, green: 0.92, blue: 0.54, alpha: 1))
    context.fillPath()
    context.setFillColor(background)
    context.fillEllipse(in: CGRect(x: 469, y: 634, width: 35, height: 35))
    let bytes = NSMutableData()
    let output = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(output, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(output))
    return bytes as Data
}

let catalog = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
for (side, path) in [
    (1024, "AppIcon.appiconset/AppIcon.png"),
    (80, "ChessLensLogo.imageset/ChessLensLogo@2x.png"),
    (120, "ChessLensLogo.imageset/ChessLensLogo@3x.png")
] {
    try makeIcon(side: side).write(to: catalog.appendingPathComponent(path))
}
