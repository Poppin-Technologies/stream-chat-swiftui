//
// Poppin (2026-11-22): styled words and Invisible Ink in a message.
//

import StreamChat
import SwiftUI
import UIKit

/// A message's words with their styles, as SwiftUI draws them (contract §3.4 `styles`,
/// 2026-11-22).
@available(iOS 15.0, *)
public enum ChatStyledText {
    /// How the words in Invisible Ink are drawn.
    public enum Ink {
        /// As they were written: their reader tapped them.
        case shown
        /// Not at all: the dust stands over their place.
        case covered
        /// As solid blocks, and nothing else of the text: the shape the dust is cut to. Same
        /// words and fonts as the text it lies on, so every block falls on its word.
        case blocks
    }

    /// `words` with `styles`. The ranges count UTF-16 units of `words`
    /// (`ChatMessage.fullText`).
    public static func make(_ words: String, styles: [ChatTextStyle], ink: Ink) -> AttributedString {
        var text = AttributedString(words)
        if ink == .blocks {
            text.swiftUI.foregroundColor = .clear
        }
        let units = words.utf16.count
        // What every unit carries, so that each stretch is styled once and whole.
        var carried = [UInt8](repeating: 0, count: units)
        for style in styles where style.fits(units: units) {
            for unit in style.offset..<(style.offset + style.length) {
                carried[unit] |= bit(style.kind)
            }
        }
        var start = 0
        while start < units {
            var end = start + 1
            while end < units, carried[end] == carried[start] {
                end += 1
            }
            let kinds = carried[start]
            if kinds != 0 {
                if let range = Range(NSRange(location: start, length: end - start), in: text) {
                    apply(kinds, to: &text, range, ink: ink)
                } else if kinds & bit(.spoiler) != 0, ink != .shown {
                    // A hidden stretch that cannot be placed: nothing of the text is shown.
                    if ink == .covered {
                        text.swiftUI.foregroundColor = .clear
                    } else {
                        text.swiftUI.backgroundColor = .black
                    }
                }
            }
            start = end
        }
        return text
    }

    private static func bit(_ kind: ChatTextStyle.Kind) -> UInt8 {
        switch kind {
        case .bold: return 1
        case .italic: return 2
        case .underline: return 4
        case .strike: return 8
        case .spoiler: return 16
        }
    }

    private static func apply(_ kinds: UInt8, to text: inout AttributedString, _ range: Range<AttributedString.Index>, ink: Ink) {
        var intent: InlinePresentationIntent = []
        if kinds & bit(.bold) != 0 { intent.insert(.stronglyEmphasized) }
        if kinds & bit(.italic) != 0 { intent.insert(.emphasized) }
        if !intent.isEmpty {
            text[range].inlinePresentationIntent = intent
        }
        if ink != .blocks {
            if kinds & bit(.underline) != 0 { text[range].swiftUI.underlineStyle = .single }
            if kinds & bit(.strike) != 0 { text[range].swiftUI.strikethroughStyle = .single }
        }
        guard kinds & bit(.spoiler) != 0 else { return }
        switch ink {
        case .shown:
            break
        case .covered:
            text[range].swiftUI.foregroundColor = .clear
        case .blocks:
            text[range].swiftUI.backgroundColor = .black
        }
    }
}

/// Which messages in Invisible Ink their reader has tapped open. A tap holds for as long as
/// the chat screen it was made on stands: the next time the chat is opened, everything is
/// covered again. Kept here and not in the bubble, because a bubble is built anew whenever its
/// row is (a reaction, a scroll away and back), and the ink must not close over that.
public final class ChatInkReveals {
    public static let shared = ChatInkReveals()

    private let lock = NSLock()
    /// Held weakly and compared as the object itself: a later screen that happens to be made
    /// where a freed one stood is another screen.
    private weak var screen: AnyObject?
    private var opened: Set<MessageId> = []

    /// `screen` is the open chat's own object (its view model).
    public func isOpen(_ messageId: MessageId, on screen: AnyObject) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return self.screen === screen && opened.contains(messageId)
    }

    public func open(_ messageId: MessageId, on screen: AnyObject) {
        lock.lock()
        defer { lock.unlock() }
        if self.screen !== screen {
            self.screen = screen
            opened = []
        }
        opened.insert(messageId)
    }
}

/// The dust that stands over hidden words or a hidden picture: specks that drift. Core
/// Animation draws them, so they keep moving whatever the app's main thread is doing and cost
/// it nothing while a chat scrolls. Under Reduce Motion the dust stands still. It fills the
/// frame it is given: cut it to the hidden part with a mask.
public struct InkDust: UIViewRepresentable {
    private let color: UIColor

    public init(color: UIColor = .white) {
        self.color = color
    }

    public func makeUIView(context: Context) -> InkDustView {
        let view = InkDustView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    public func updateUIView(_ view: InkDustView, context: Context) {
        view.show(color: color, still: context.environment.accessibilityReduceMotion)
    }
}

public final class InkDustView: UIView {
    override public class var layerClass: AnyClass { CAEmitterLayer.self }

    private var color: UIColor = .white
    private var still = false
    private var drawnFor: CGSize?

    func show(color: UIColor, still: Bool) {
        guard color != self.color || still != self.still else { return }
        self.color = color
        self.still = still
        drawnFor = nil
        setNeedsLayout()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != drawnFor else { return }
        drawnFor = bounds.size
        emit()
    }

    private func emit() {
        guard let emitter = layer as? CAEmitterLayer else { return }
        let size = bounds.size
        guard size.width > 0, size.height > 0 else {
            emitter.emitterCells = nil
            return
        }
        let speck = CAEmitterCell()
        speck.contents = Self.speck.cgImage
        speck.contentsScale = Self.speck.scale
        speck.color = color.cgColor
        speck.alphaRange = 0.5
        speck.alphaSpeed = -0.3
        speck.scale = 0.36
        speck.scaleRange = 0.16
        speck.lifetime = Float(Self.life)
        speck.lifetimeRange = 0.5
        speck.velocity = 5
        speck.velocityRange = 5
        speck.emissionRange = .pi * 2
        // One speck for every `areaPerSpeck` square points of the cover, at any moment.
        let living = min(max(size.width * size.height / Self.areaPerSpeck, 24), 1800)
        speck.birthRate = Float(living / CGFloat(Self.life))

        emitter.emitterShape = .rectangle
        emitter.emitterMode = .surface
        emitter.emitterPosition = CGPoint(x: size.width / 2, y: size.height / 2)
        emitter.emitterSize = size
        emitter.masksToBounds = true
        emitter.emitterCells = [speck]
        if still {
            // The dust as it stands one lifetime in, held there.
            emitter.speed = 0
            emitter.beginTime = 0
            emitter.timeOffset = Self.life
        } else {
            // Begun one lifetime ago, so the cover is whole from its first frame.
            emitter.speed = 1
            emitter.timeOffset = 0
            emitter.beginTime = CACurrentMediaTime() - Self.life
        }
    }

    private static let life: CFTimeInterval = 1.4
    private static let areaPerSpeck: CGFloat = 11
    private static let speck: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
        UIColor.white.setFill()
        context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 4, height: 4))
    }
}

// MARK: - A photo or a video under Invisible Ink (2026-11-22)

private struct ChatInkScreenKey: EnvironmentKey {
    static var defaultValue: AnyObject? { nil }
}

public extension EnvironmentValues {
    /// The open chat screen's own object (its view model): what a tap on Invisible Ink holds
    /// for (`ChatInkReveals`). nil outside a chat screen: a tap then holds for its row only.
    var chatInkScreen: AnyObject? {
        get { self[ChatInkScreenKey.self] }
        set { self[ChatInkScreenKey.self] = newValue }
    }
}

/// Decides whether a message's photos and videos still stand under Invisible Ink, and takes
/// the tap that uncovers them. The tap holds for as long as the chat screen stands
/// (`ChatInkReveals`), so a row that is built anew (a reaction, a scroll away and back, the
/// hold menu) does not cover again what its reader has opened.
public struct InkMediaGate<Content: View>: View {
    @Environment(\.chatInkScreen) private var screen
    @State private var tapped = false

    private let message: ChatMessage
    private let part: String
    private let content: (Bool, @escaping () -> Void) -> Content

    /// `part` names one tile of a message whose tiles open one by one (its videos); empty for
    /// a tile that stands for all of them (a photo, a grid, a stack). `content` gets whether
    /// the tile is covered, and what a tap on the cover does.
    public init(
        message: ChatMessage,
        part: String = "",
        @ViewBuilder content: @escaping (_ covered: Bool, _ uncover: @escaping () -> Void) -> Content
    ) {
        self.message = message
        self.part = part
        self.content = content
    }

    public var body: some View {
        content(covered, uncover)
    }

    /// Apart from the message's words, which open at their own tap.
    private var revealId: MessageId { message.id + "#media" + part }

    /// Read on every draw and not kept: a row that is built anew starts with `tapped` false,
    /// and must not show its dust for a frame over a photo that was opened.
    private var covered: Bool {
        guard message.mediaIsUnderInk, !tapped else { return false }
        guard let screen = screen else { return true }
        return !ChatInkReveals.shared.isOpen(revealId, on: screen)
    }

    private func uncover() {
        if let screen = screen {
            ChatInkReveals.shared.open(revealId, on: screen)
        }
        withAnimation(.easeOut(duration: 0.35)) {
            tapped = true
        }
    }
}

public extension View {
    /// A photo or video tile under Invisible Ink: while `covered` it is blurred past reading
    /// with the dust over it, its own taps stand down, and one tap on it calls `uncover`.
    /// `cornerRadius` is the tile's own: the cover is cut to it. Only for the tiles of a
    /// message that carries the mark (`ChatMessage.mediaIsUnderInk`), so every other tile is
    /// drawn exactly as before.
    func inkCover(_ covered: Bool, cornerRadius: CGFloat = 0, uncover: @escaping () -> Void) -> some View {
        modifier(InkMediaCover(covered: covered, cornerRadius: cornerRadius, uncover: uncover))
    }
}

struct InkMediaCover: ViewModifier {
    let covered: Bool
    let cornerRadius: CGFloat
    let uncover: () -> Void

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .blur(radius: covered ? 30 : 0, opaque: covered)
            .allowsHitTesting(!covered)
            // VoiceOver reads the cover, never the photo under it.
            .accessibilityHidden(covered)
            .overlay(
                ZStack {
                    if covered {
                        // Under the specks, so the tile reads as covered wherever no speck
                        // happens to be, on a bright photo too.
                        Color.black.opacity(0.22)
                        InkDust()
                    }
                }
                .allowsHitTesting(false)
            )
            // hit-clip: the blur spills past the tile; the cut and the touch area are the tile's own shape
            .clipShape(shape)
            .contentShape(shape)
            .overlay(
                ZStack {
                    if covered {
                        // The tap is taken the way a tile takes its own (`LazyLoadingImage`),
                        // so a hold still reaches the row.
                        Color.clear
                            .contentShape(shape)
                            .highPriorityGesture(TapGesture().onEnded { uncover() })
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Hidden with Invisible Ink")
                            .accessibilityHint("Double tap to show")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("chat-ink-media-covered")
                    }
                }
            )
    }
}
