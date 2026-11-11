import CoreGraphics

/// Where the live preview and the chip row go around the line being typed (screen coordinates, y up): both above
/// the line when both fit under the top of the screen, else both below it, the chips always on the far side of the
/// preview, so the row never jumps between above and below it.
public enum StackPlacement {
    public static let gap: CGFloat = 6

    /// Whether a box of `height`, with `reserve` more above it (the chips; 0 for none), fits above `line`.
    public static func fitsAbove(_ line: CGRect, height: CGFloat, reserve: CGFloat, top: CGFloat) -> Bool {
        line.maxY + gap + height + (reserve > 0 ? gap + reserve : 0) <= top
    }

    /// The y of a box of `height` placed above `line` when it fits (with `reserve`), else below it.
    public static func y(for line: CGRect, height: CGFloat, reserve: CGFloat = 0, top: CGFloat) -> CGFloat {
        fitsAbove(line, height: height, reserve: reserve, top: top) ? line.maxY + gap : line.minY - height - gap
    }

    /// The y of a box of `height` on the far side of `preview` from `line`: above a preview above the line,
    /// below a preview below it.
    public static func y(beside preview: CGRect, of line: CGRect, height: CGFloat) -> CGFloat {
        preview.minY >= line.midY ? preview.maxY + gap : preview.minY - height - gap
    }
}
