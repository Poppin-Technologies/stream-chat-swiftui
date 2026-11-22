//
// Poppin (2026-11-22): text styles in the message field.
//

import StreamChat
import SwiftUI
import UIKit

/// Text styles and Invisible Ink in a chat (contract §3.4 `styles`, 2026-11-22): bold, italic,
/// underline, strikethrough, and words hidden until their reader taps them. The styles ride
/// beside a message's plain text as ranges, so the field below keeps them as attributes of its
/// text and never as marks typed into it.
public enum ChatTextStyles {
    /// Whether this build offers the Format menu on selected words: the app's own switch. The
    /// server's feature is asked on top of it (`isOffered(by:)`). Styles that arrive are always
    /// drawn, whatever this says.
    public static var appOffers: () -> Bool = { false }

    /// The name a server gives the feature in `hello.features`.
    public static let serverFeature = "textStyles"

    /// The Format menu is offered: the app's switch is on and the server takes styles. A
    /// server from before them would send hidden words out in the open.
    public static func isOffered(by client: ChatClient) -> Bool {
        appOffers() && client.serverFeatures.contains(serverFeature)
    }

    /// The most ranges one message carries: the server refuses more.
    public static let mostPerMessage = 100
}

public extension ChatTextStyle.Kind {
    /// The rows of the Format menu, top to bottom.
    static let formatMenu: [ChatTextStyle.Kind] = [.bold, .italic, .underline, .strike, .spoiler]

    /// The row's name in the Format menu.
    var menuTitle: String {
        switch self {
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .underline: return "Underline"
        case .strike: return "Strikethrough"
        case .spoiler: return "Invisible Ink"
        }
    }

    /// The row's picture in the Format menu.
    var menuSymbol: String {
        switch self {
        case .bold: return "bold"
        case .italic: return "italic"
        case .underline: return "underline"
        case .strike: return "strikethrough"
        case .spoiler: return "sparkles"
        }
    }
}

/// What the message field and the composer's view model share about the styles of the draft.
/// The field's text storage is the one place that holds them; this is what the field last
/// told, kept where a send can read it. A plain reference on purpose, never observed: a style
/// changes nothing else on screen, so no view is drawn again over it.
public final class ComposerTextStyleBridge {
    /// The styled ranges of the field's text.
    public internal(set) var styles: [ChatTextStyle] = []

    /// Words on their way into the field with the styles they carry (none, for plain words): a
    /// message opened for an edit, a draft handed back after a send that failed. The field
    /// takes them with exactly that text.
    private var arriving: (text: String, styles: [ChatTextStyle])?

    public init() {}

    /// The draft holds styled words.
    public var hasStyles: Bool { !styles.isEmpty }

    /// The styles to send with `text`: the ones that lie inside it, as many as a message may
    /// carry.
    public func styles(fitting text: String) -> [ChatTextStyle] {
        let units = text.utf16.count
        return Array(styles.filter { $0.fits(units: units) }.prefix(ChatTextStyles.mostPerMessage))
    }

    func expect(text: String, styles: [ChatTextStyle]) {
        arriving = (text, styles)
        self.styles = styles
    }

    func takeArriving(with text: String) -> [ChatTextStyle]? {
        guard let arriving, arriving.text == text else { return nil }
        self.arriving = nil
        return arriving.styles
    }

    func clear() {
        arriving = nil
        styles = []
    }
}

private struct ComposerTextStylesKey: EnvironmentKey {
    static let defaultValue: ComposerTextStyleBridge? = nil
}

extension EnvironmentValues {
    /// The draft's styles, shared by the composer's view model and its field. Nil where a
    /// field stands alone: it then stays plain.
    var composerTextStyles: ComposerTextStyleBridge? {
        get { self[ComposerTextStylesKey.self] }
        set { self[ComposerTextStylesKey.self] = newValue }
    }
}

// MARK: - The field

extension NSAttributedString.Key {
    /// The field's own mark on a styled character: the one thing the styles are read from.
    /// What the eye sees (the font, the lines, the highlight) is painted from these marks.
    static func chatTextStyle(_ kind: ChatTextStyle.Kind) -> NSAttributedString.Key {
        NSAttributedString.Key("poppin.chatTextStyle.\(kind.rawValue)")
    }
}

extension InputTextView {
    private var plainFont: UIFont {
        InjectedValues[\.utils].composerConfig.inputFont
    }

    var plainTextAttributes: [NSAttributedString.Key: Any] {
        [.font: plainFont, .foregroundColor: InjectedValues[\.colors].text]
    }

    private var wholeText: NSRange {
        NSRange(location: 0, length: textStorage.length)
    }

    /// The text holds styled words.
    var hasTextStyles: Bool {
        var found = false
        textStorage.enumerateAttributes(in: wholeText, options: .longestEffectiveRangeNotRequired) { attributes, _, stop in
            if ChatTextStyle.Kind.allCases.contains(where: { attributes[.chatTextStyle($0)] != nil }) {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    /// The styled ranges of the text, read from its marks.
    var textStyleRanges: [ChatTextStyle] {
        var ranges: [ChatTextStyle] = []
        for kind in ChatTextStyle.Kind.allCases {
            textStorage.enumerateAttribute(.chatTextStyle(kind), in: wholeText) { value, range, _ in
                if value != nil {
                    ranges.append(ChatTextStyle(kind: kind, range: range))
                }
            }
        }
        return ranges.sorted { ($0.offset, $0.length) < ($1.offset, $1.length) }
    }

    /// Every character of `range` carries `kind`.
    func carries(_ kind: ChatTextStyle.Kind, in range: NSRange) -> Bool {
        guard range.length > 0, NSMaxRange(range) <= textStorage.length else { return false }
        var carried = true
        textStorage.enumerateAttribute(.chatTextStyle(kind), in: range) { value, _, stop in
            if value == nil {
                carried = false
                stop.pointee = true
            }
        }
        return carried
    }

    /// Puts `kind` on `range`, or takes it off when all of the range carries it already.
    func toggleTextStyle(_ kind: ChatTextStyle.Kind, in range: NSRange) {
        guard range.length > 0, NSMaxRange(range) <= textStorage.length else { return }
        if carries(kind, in: range) {
            textStorage.removeAttribute(.chatTextStyle(kind), range: range)
        } else {
            textStorage.addAttribute(.chatTextStyle(kind), value: true, range: range)
        }
        paintTextStyles()
    }

    /// Marks the ranges of `styles` that lie inside the text.
    func markTextStyles(_ styles: [ChatTextStyle]) {
        let units = textStorage.length
        for style in styles where style.fits(units: units) {
            textStorage.addAttribute(.chatTextStyle(style.kind), value: true, range: style.range)
        }
        paintTextStyles()
    }

    /// Takes every mark off: the text is plain again.
    func clearTextStyles() {
        for kind in ChatTextStyle.Kind.allCases {
            textStorage.removeAttribute(.chatTextStyle(kind), range: wholeText)
        }
        paintTextStyles()
        typingAttributes = plainTextAttributes
    }

    /// Replaces only the part of the text that differs from `newText`, as plain words, so the
    /// styled words around it keep their styles.
    func replaceChangedPart(with newText: String) {
        let old = textStorage.string as NSString
        let new = newText as NSString
        let shared = min(old.length, new.length)
        var head = 0
        while head < shared, old.character(at: head) == new.character(at: head) {
            head += 1
        }
        var tail = 0
        while tail < shared - head,
              old.character(at: old.length - 1 - tail) == new.character(at: new.length - 1 - tail) {
            tail += 1
        }
        let replaced = NSRange(location: head, length: old.length - head - tail)
        let part = new.substring(with: NSRange(location: head, length: new.length - head - tail))
        textStorage.replaceCharacters(in: replaced, with: NSAttributedString(string: part, attributes: plainTextAttributes))
    }

    /// Paints what the eye sees from the marks: the font, the lines, the highlight of the
    /// hidden words. It changes only what is not as it should be already.
    func paintTextStyles() {
        let storage = textStorage
        guard storage.length > 0 else {
            typingAttributes = plainTextAttributes
            return
        }
        var runs: [(range: NSRange, attributes: [NSAttributedString.Key: Any])] = []
        storage.enumerateAttributes(in: wholeText) { attributes, range, _ in
            runs.append((range, attributes))
        }
        let plain = plainFont
        var fonts: [Int: UIFont] = [:]
        var editing = false
        func change(_ edit: () -> Void) {
            if !editing {
                storage.beginEditing()
                editing = true
            }
            edit()
        }
        for run in runs {
            let marked = { (kind: ChatTextStyle.Kind) in run.attributes[.chatTextStyle(kind)] != nil }
            let bold = marked(.bold)
            let italic = marked(.italic)
            let slot = (bold ? 1 : 0) + (italic ? 2 : 0)
            let font = fonts[slot] ?? Self.styledFont(plain, bold: bold, italic: italic)
            fonts[slot] = font
            // A character the font cannot draw (an emoji) carries a stand-in font; the font it
            // was given is kept beside it.
            let given = (run.attributes[Self.givenFontKey] ?? run.attributes[.font]) as? UIFont
            if given != font {
                change { storage.addAttribute(.font, value: font, range: run.range) }
            }
            for (line, wanted) in [(NSAttributedString.Key.underlineStyle, marked(.underline)), (.strikethroughStyle, marked(.strike))] {
                let drawn = (run.attributes[line] as? Int ?? 0) != 0
                guard drawn != wanted else { continue }
                change {
                    if wanted {
                        storage.addAttribute(line, value: NSUnderlineStyle.single.rawValue, range: run.range)
                    } else {
                        storage.removeAttribute(line, range: run.range)
                    }
                }
            }
            let hidden = marked(.spoiler)
            if (run.attributes[.backgroundColor] != nil) != hidden {
                change {
                    if hidden {
                        storage.addAttribute(.backgroundColor, value: Self.hiddenWordsHighlight, range: run.range)
                    } else {
                        storage.removeAttribute(.backgroundColor, range: run.range)
                    }
                }
            }
        }
        if editing {
            storage.endEditing()
        }
    }

    private static let givenFontKey = NSAttributedString.Key("NSOriginalFont")

    /// How the field shows words in Invisible Ink while they are written: a soft highlight.
    private static var hiddenWordsHighlight: UIColor {
        InjectedValues[\.colors].text.withAlphaComponent(0.26)
    }

    private static func styledFont(_ plain: UIFont, bold: Bool, italic: Bool) -> UIFont {
        guard bold || italic else { return plain }
        var traits = plain.fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if let descriptor = plain.fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: descriptor, size: plain.pointSize)
        }
        // A font with no such face: the system's.
        let system = UIFont.systemFont(ofSize: plain.pointSize, weight: bold ? .bold : .regular)
        guard italic, let slanted = system.fontDescriptor.withSymbolicTraits(bold ? [.traitBold, .traitItalic] : .traitItalic) else {
            return system
        }
        return UIFont(descriptor: slanted, size: plain.pointSize)
    }
}

// MARK: - The field's coordinator

extension ComposerTextInputView.Coordinator: NSTextStorageDelegate {
    /// A typed or pasted character takes a style only when it lands INSIDE styled words: with a
    /// styled character on both sides. At the end of styled words the next character is plain,
    /// so a person who made one word bold goes on writing plain. UIKit alone would carry the
    /// style on (a new character takes the attributes of the one before it), with no way to
    /// stop it but a second trip to the menu.
    ///
    /// Words put in the PLACE of others (a suggestion tapped, a correction, typing over a
    /// selection) are left as UIKit hands them over, with the marks of the words they replace:
    /// a corrected word in Invisible Ink stays hidden.
    func textStorage(
        _ textStorage: NSTextStorage,
        willProcessEditing editedMask: NSTextStorage.EditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard paintsStyles, !settingTextByCode, editedMask.contains(.editedCharacters), editedRange.length > 0 else { return }
        // Only characters that came in BETWEEN others are judged by their neighbours.
        guard editedRange.length == delta else { return }
        let end = NSMaxRange(editedRange)
        for kind in ChatTextStyle.Kind.allCases {
            let mark = NSAttributedString.Key.chatTextStyle(kind)
            let before = editedRange.location > 0
                && textStorage.attribute(mark, at: editedRange.location - 1, effectiveRange: nil) != nil
            let after = end < textStorage.length && textStorage.attribute(mark, at: end, effectiveRange: nil) != nil
            if before && after {
                textStorage.addAttribute(mark, value: true, range: editedRange)
            } else {
                textStorage.removeAttribute(mark, range: editedRange)
            }
        }
    }

    /// The Format menu on selected words: Bold, Italic, Underline, Strikethrough, Invisible
    /// Ink. A row that all of the selection carries shows its tick and takes the style off.
    @available(iOS 16.0, *)
    func textView(
        _ textView: UITextView,
        editMenuForTextIn range: NSRange,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        guard range.length > 0, styles != nil, let field = textView as? InputTextView,
              ChatTextStyles.isOffered(by: InjectedValues[\.chatClient])
        else { return nil }
        let rows = ChatTextStyle.Kind.formatMenu.map { kind in
            UIAction(
                title: kind.menuTitle,
                image: UIImage(systemName: kind.menuSymbol),
                state: field.carries(kind, in: range) ? .on : .off
            ) { [weak self, weak field] _ in
                guard let self, let field else { return }
                self.toggle(kind, in: range, of: field)
            }
        }
        let format = UIMenu(title: "Format", image: UIImage(systemName: "textformat"), children: rows)
        var menu = suggestedActions
        menu.insert(format, at: min(1, menu.count))
        return UIMenu(children: menu)
    }

    func toggle(_ kind: ChatTextStyle.Kind, in range: NSRange, of field: InputTextView) {
        paintsStyles = true
        field.toggleTextStyle(kind, in: range)
        styles?.styles = field.textStyleRanges
        // Bold words are wider: the field may need another line.
        updateHeight(field, shouldAnimate: false)
    }

    /// The text changed under the person's hands: paint what the marks ask for, and tell the
    /// view model's side what the styles are now. While a word is still being composed (a
    /// keyboard that builds characters) the paint waits, so the keyboard's own marking stays.
    func textStylesDidChange(in field: InputTextView) {
        guard paintsStyles, let styles else { return }
        if field.markedTextRange == nil {
            field.paintTextStyles()
        }
        styles.styles = field.textStyleRanges
    }

    /// The view model set the field's text.
    func setText(_ newText: String, in field: InputTextView) {
        let arriving = styles?.takeArriving(with: newText)
        if let arriving, !arriving.isEmpty {
            // Words that come with their styles: an edit, a draft handed back.
            paintsStyles = true
            settingTextByCode = true
            field.textStorage.setAttributedString(NSAttributedString(string: newText, attributes: field.plainTextAttributes))
            settingTextByCode = false
            field.markTextStyles(arriving)
        } else if paintsStyles, arriving == nil, !newText.isEmpty, field.hasTextStyles {
            // The view model changed a part of the text (a picked mention).
            settingTextByCode = true
            field.replaceChangedPart(with: newText)
            settingTextByCode = false
            field.paintTextStyles()
        } else {
            field.text = newText
            if paintsStyles {
                // Nothing of the styled words before may hang on to the new ones.
                field.clearTextStyles()
            } else {
                // A field that shows no styled words sends none: styles kept for words that
                // arrived changed, or for a field that was built anew, describe nothing here.
                styles?.clear()
            }
        }
        if paintsStyles {
            styles?.styles = field.textStyleRanges
        }
    }
}
