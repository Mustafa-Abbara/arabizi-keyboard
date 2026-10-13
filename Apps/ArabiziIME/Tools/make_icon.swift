// Draws the menu-bar icon (the letter ع) as a TIFF, so no binary image is committed.
// Usage: swift make_icon.swift <output.tiff>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 16, height: 16)
let image = NSImage(size: size)
for scale in [1, 2] {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 16 * scale, pixelsHigh: 16 * scale, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("could not create bitmap") }
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
        .foregroundColor: NSColor.black,
    ]
    let letter = NSAttributedString(string: "ع", attributes: attributes)
    let bounds = letter.size()
    letter.draw(at: NSPoint(x: (size.width - bounds.width) / 2, y: (size.height - bounds.height) / 2))
    NSGraphicsContext.restoreGraphicsState()
    image.addRepresentation(rep)
}
guard let tiff = image.tiffRepresentation else { fatalError("could not encode TIFF") }
try tiff.write(to: output)
