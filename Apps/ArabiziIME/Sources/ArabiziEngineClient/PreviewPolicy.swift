/// When the keyboard converts what is typed ahead of Enter, and when it shows the preview box. The two are separate:
/// with the live preview off the engine still converts ahead, so Enter finds a ready answer instead of waiting for
/// the model (as on Windows, `Core.preview` in HarfiCoreC).
public enum PreviewPolicy {
    /// Convert ahead whenever the typed text has letters and no word is being fixed, whatever the preview setting.
    public static func convertsAhead(_ typed: String, fixing: Bool) -> Bool {
        !fixing && typed.contains(where: \.isLetter)
    }

    /// Show the preview box only when the user wants it, and not while a word is being fixed.
    public static func shows(livePreview: Bool, fixing: Bool) -> Bool {
        livePreview && !fixing
    }
}
