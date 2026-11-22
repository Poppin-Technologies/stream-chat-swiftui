//
// Poppin (2026-11-21): two or more photos in one message draw as a stack of cards, the way Messages
// shows them. The front card has its own shape, the next three fan out behind it on the right, the
// one just passed peeks on the left. A sideways swipe turns the stack, a tap opens the photo in front,
// and "8 Photos" above it opens the grid. The stack carries no bubble.
//

import StreamChat
import SwiftUI
import UIKit

/// A photo's own shape, from the sizes its message carries.
enum PhotoShape {
    /// Width over height, nil when the wire did not carry the sizes.
    static func ratio(of attachment: ChatMessageImageAttachment) -> CGFloat? {
        guard let width = attachment.originalWidth, let height = attachment.originalHeight,
              width > 0, height > 0 else { return nil }
        return CGFloat(width / height)
    }

    /// The largest size of that shape inside `box`. A very long or very wide photo is cut at 1:2 and 2:1.
    static func size(ratio: CGFloat, in box: CGSize) -> CGSize {
        let shape = min(max(ratio, 0.5), 2)
        if box.width / shape <= box.height {
            return CGSize(width: box.width, height: (box.width / shape).rounded())
        }
        return CGSize(width: (box.height * shape).rounded(), height: box.height)
    }
}

/// The part of the screen a photo stack takes. The row's two sideways drags (`TimeSlideDrag` in
/// MessageListView.swift, `ReplySwipeDrag` in MessageContainerView.swift) are simultaneous gestures on
/// ancestors of the stack and keep firing while the stack's own scroller pans, so each asks here whether
/// its touch began on a stack and stands down. It is a plain UIKit view asked at that moment, on purpose:
/// a gesture on the stack that begins at touch-down takes the hold (the message menu) away from the row,
/// and a frame noted earlier is stale once the list has scrolled.
final class PhotoStackArea: UIView {
    private static let all = NSHashTable<PhotoStackArea>.weakObjects()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        Self.all.add(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// `point` in the window's coordinates, which is SwiftUI's global space.
    static func contains(_ point: CGPoint) -> Bool {
        guard all.count > 0 else { return false }
        return all.allObjects.contains { area in
            area.window != nil && area.convert(area.bounds, to: nil).contains(point)
        }
    }
}

private struct PhotoStackAreaMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> PhotoStackArea { PhotoStackArea() }
    func updateUIView(_ uiView: PhotoStackArea, context: Context) {}
}

/// Where one card stands for a given distance of its page from the front page.
struct PhotoStackPose {
    /// Every card is drawn twice. `main` draws it while it waits, stands in front and swings out, with
    /// the lower index on top. `passed` lies under all of `main` and draws the card from the middle of
    /// that swing on: that is the moment it goes behind the stack. So which card covers which follows
    /// from where the pages stand alone, never from a state that has to keep up with the scroller.
    enum Layer {
        case main
        case passed
    }

    var x: CGFloat
    var degrees: Double
    var scale: CGFloat
    var anchor: UnitPoint
    var brightness: Double
    var opacity: Double

    /// `pageX`: how far the card's page stands right of the front one, negative once it is passed.
    init(pageX: CGFloat, page: CGFloat, cardWidth: CGFloat, fanStep: CGFloat, peek: CGFloat, layer: Layer) {
        let pages = pageX / max(1, page)
        if pages >= 0 {
            // Waiting behind the front card: pinned back on the stack and fanned out to the right.
            let depth = min(pages, 3)
            x = -pageX + depth * fanStep
            degrees = Double(depth) * 2.2
            scale = 1 - depth * 0.05
            anchor = .trailing
            brightness = -Double(depth) * 0.07
            opacity = layer == .main ? Double(min(max(4 - pages, 0), 1)) : 0
        } else {
            // Passed: it swings out to the left, then tucks in behind the new front card and peeks.
            let passed = min(-pages, 1)
            let swing = sin(.pi * passed)
            x = -pageX - swing * cardWidth * 0.45 - passed * peek
            degrees = -(Double(swing) * 7 + Double(passed) * 2.5)
            scale = 1 - passed * 0.06
            anchor = .leading
            brightness = -Double(passed) * 0.12
            switch layer {
            case .main:
                // Over the stack until the swing is widest, then it dissolves: the `passed` copy
                // already stands in the same place under the stack.
                opacity = Double(min(max((pages + 0.6) / 0.2, 0), 1))
            case .passed:
                // The card before it fades as this one takes the peek.
                opacity = pages <= -0.4 ? Double(min(max(2 + pages, 0), 1)) : 0
            }
        }
    }
}

/// The stack itself. A real sideways paged scroller, so the system tells a turn of the stack from a
/// scroll of the chat. Every page is as wide as the row and holds one card; the card is drawn pinned
/// back onto the stack (`PhotoStackPose`), so only the picture moves and the pages stay the touch areas.
@available(iOS 17.0, *)
struct PhotoStackView: View {
    @Injected(\.colors) private var colors
    @Injected(\.fonts) private var fonts

    let message: ChatMessage
    let width: CGFloat
    /// Poppin (2026-11-22): the photos stand under Invisible Ink: blurred past reading, the
    /// dust over the card in front, and the stack does not turn. The caller's taps uncover it.
    var covered = false
    /// A tap on the stack: the index of the photo in front.
    let photoTapped: (Int) -> Void
    /// A tap on "8 Photos".
    let gridTapped: () -> Void

    /// Room right of the front card for the three cards that fan out.
    private static let fanRoom: CGFloat = 36
    /// Room left of it for the passed card.
    private static let peekRoom: CGFloat = 18
    /// Room above and under the tallest card for its shadow. A card in mid swing rises higher and draws
    /// over its neighbours for that moment.
    private static let rise: CGFloat = 3
    private static let cornerRadius: CGFloat = 18

    private var attachments: [ChatMessageImageAttachment] { message.imageAttachments }
    private var isOwn: Bool { message.isSentByCurrentUser }

    private var box: CGSize {
        let boxWidth = max(120, width - Self.fanRoom - Self.peekRoom)
        return CGSize(width: boxWidth, height: (boxWidth * 4 / 3).rounded())
    }

    var body: some View {
        let box = self.box
        // A photo with no size on the wire draws as a portrait card, the shape most phone photos have.
        let sizes = attachments.map { PhotoShape.size(ratio: PhotoShape.ratio(of: $0) ?? 0.75, in: box) }
        let seat = sizes.map(\.width).max() ?? box.width
        // One height for the row, its tallest card: nothing under the stack jumps while it turns.
        let height = (sizes.map(\.height).max() ?? box.height) + 2 * Self.rise

        VStack(alignment: isOwn ? .trailing : .leading, spacing: 0) {
            countLabel
            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    pages(.passed, sizes: sizes, seat: seat, height: height)
                        .allowsHitTesting(false)
                    pages(.main, sizes: sizes, seat: seat, height: height)
                }
                .modifier(InkStackBlur(marked: message.mediaIsUnderInk, covered: covered))
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .scrollDisabled(covered)
            .frame(width: width, height: height)
            .background(PhotoStackAreaMarker())
            .overlay(alignment: .topLeading) {
                if covered, let front = sizes.first {
                    inkDust(over: front, seat: seat, height: height)
                }
            }
        }
        .frame(width: width, alignment: isOwn ? .trailing : .leading)
        .accessibilityIdentifier("PhotoStackView")
    }

    /// The dust over the card in front, where it rests while the stack stands under Invisible
    /// Ink (the stack does not turn then, so the first photo stays in front).
    private func inkDust(over front: CGSize, seat: CGFloat, height: CGFloat) -> some View {
        let seatLeading = isOwn ? width - Self.fanRoom - seat : Self.peekRoom
        return ZStack {
            Color.black.opacity(0.22)
            InkDust()
        }
        .frame(width: front.width, height: front.height)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .padding(.leading, seatLeading + (seat - front.width) / 2)
        .padding(.top, (height - front.height) / 2)
        // hit-clip: a still cover; the page under it takes the tap
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private var countLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 13, weight: .semibold))
            Text("\(attachments.count) Photos")
                .font(fonts.subheadlineBold)
        }
        .foregroundColor(colors.tintColor)
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .highPriorityGesture(
            TapGesture().onEnded { gridTapped() }
        )
        .accessibilityIdentifier("PhotoStackCount")
    }

    /// One layer of the stack: a page per photo, side by side.
    private func pages(_ layer: PhotoStackPose.Layer, sizes: [CGSize], seat: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(attachments.indices, id: \.self) { index in
                page(index, layer: layer, size: sizes[index], seat: seat, height: height)
                    .zIndex(Double(layer == .main ? -index : index))
            }
        }
    }

    private func page(
        _ index: Int,
        layer: PhotoStackPose.Layer,
        size: CGSize,
        seat: CGFloat,
        height: CGFloat
    ) -> some View {
        let pageWidth = width
        let fanStep = Self.fanRoom / 3
        let peek = Self.peekRoom
        // Where the card's leading edge rests inside its own page: centred on the stack's seat.
        let seatLeading = isOwn ? pageWidth - Self.fanRoom - seat : Self.peekRoom
        let rest = seatLeading + (seat - size.width) / 2

        return ZStack(alignment: .topLeading) {
            if layer == .main {
                // The page takes the tap, the same way one photo does (`LazyLoadingImage`), so a hold
                // still reaches the row. The card is a picture only (law: decorations never take a
                // touch), because it is drawn away from its page.
                Color.clear
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        TapGesture().onEnded { photoTapped(index) }
                    )
            }
            card(index, size: size, showsUpload: layer == .main)
                .visualEffect { content, proxy in
                    let pose = PhotoStackPose(
                        pageX: proxy.frame(in: .scrollView).minX - rest,
                        page: pageWidth,
                        cardWidth: size.width,
                        fanStep: fanStep,
                        peek: peek,
                        layer: layer
                    )
                    return content
                        .scaleEffect(pose.scale, anchor: pose.anchor)
                        .rotationEffect(.degrees(pose.degrees))
                        .offset(x: pose.x)
                        .brightness(pose.brightness)
                        .opacity(pose.opacity)
                }
                .padding(.leading, rest)
                .padding(.top, (height - size.height) / 2)
                .allowsHitTesting(false)
        }
        .frame(width: pageWidth, height: height, alignment: .topLeading)
    }

    /// Every card loads when the row appears: the three behind the front one show, and a turn must not
    /// wait for a file.
    private func card(_ index: Int, size: CGSize, showsUpload: Bool) -> some View {
        let attachment = attachments[index]
        let source = attachment.uploadingState?.localFileURL ?? attachment.imageURL
        return LazyLoadingImage(source: source, width: size.width, height: size.height)
            .withUploadingStateIndicator(for: showsUpload ? attachment.uploadingState : nil, url: source)
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.28), radius: 5, x: 0, y: 2)
    }
}

/// The cards of a stack under Invisible Ink, blurred past reading. Asked by the message's mark
/// and not by `covered`, so a stack keeps its identity through the tap that uncovers it, and a
/// message without the mark is drawn exactly as before.
@available(iOS 17.0, *)
private struct InkStackBlur: ViewModifier {
    let marked: Bool
    let covered: Bool

    func body(content: Content) -> some View {
        if marked {
            content.blur(radius: covered ? 26 : 0)
        } else {
            content
        }
    }
}
