//
//  ReplyContextStack.swift
//  Poppin: a reply the way Apple Messages draws it (measured 2026-11-10 on a 430pt phone).
//
//  Replies that follow their original, or each other, are one run. A run that stands away
//  from its original carries the original above its first reply, as an outlined block on its
//  sender's side (`ReplyContextStack`). A grey line in the leading gutter runs through the
//  whole run (`ReplyThreadLine`): it starts under an original on the leading side (with a
//  stub beside one on the trailing side), stops above a reply on the leading side and picks
//  up under it, passes a reply on the trailing side with a small loop, and ends at the last
//  one with a stub. SwiftUI only: the chat proof harness (scripts/ui-proof/chat-bubble-twin)
//  compiles this file as it is.
//

import SwiftUI

/// The numbers of Messages' reply: the row, its line, and the reply view's backdrop. Distances
/// along x are measured from the row's padded leading edge (the list pads its rows by
/// `MessagePaddings.horizontal`).
public struct ReplyStyle: Sendable {
    public var lineWidth: CGFloat
    public var color: Color
    /// Centre of the line's vertical part in a chat that shows no faces. Where faces show,
    /// the line runs down the faces' centre.
    public var spineX: CGFloat
    /// Where a stub that points at a bubble ends (its round end included).
    public var stubEndX: CGFloat
    /// Radius of the turn between the vertical part and a stub, on the line's centre.
    public var cornerRadius: CGFloat
    /// A stub's centre sits this far under the middle of the block it points at.
    public var quoteStubDrop: CGFloat
    public var replyStubDrop: CGFloat
    /// The line starts this far under a block on the leading side, and stops this far above
    /// a reply (or its sender's face) on the leading side.
    public var clearance: CGFloat
    /// The line starts this far under the face of the original's sender.
    public var faceClearance: CGFloat
    /// The loop beside a reply on the trailing side that the line passes: the line leans
    /// `loopBump` toward the bubble over `loopReach` above and below the bubble's middle,
    /// and carries a ring of `loopRadius` (on the line's centre) there.
    public var loopBump: CGFloat
    public var loopRadius: CGFloat
    public var loopReach: CGFloat
    /// From the original's bottom to the top of the row under it: both on one side, on
    /// opposite sides, and when that row opens with its sender's name.
    public var gapSameSide: CGFloat
    public var gapAcross: CGFloat
    public var gapBeforeName: CGFloat
    /// The same three with "N Replies" between the two.
    public var gapSameSideCounted: CGFloat
    public var gapAcrossCounted: CGFloat
    public var gapBeforeNameCounted: CGFloat
    /// A thread stands apart from the messages around it. Its first block (the original
    /// itself, or its outlined copy above a run) stands this far under the row before it,
    /// when that row is a message (a date line keeps its own distance)...
    public var quoteTopInset: CGFloat
    /// ...and this far lies between the last bubble of a run of replies and a message after it.
    public var runEndGap: CGFloat
    /// The face of the original's sender, in a chat that shows faces.
    public var faceSize: CGFloat
    public var faceOpacity: Double
    public var faceSpacing: CGFloat
    /// "N Replies" seated under a block (`replyCountSeat`): this far under it, and this far
    /// further in when the line runs beside it.
    public var countSpacing: CGFloat
    public var countShiftBesideLine: CGFloat
    /// How far a date line that follows closes up to the "1 Reply" line above it.
    public var countTuckBeforeDate: CGFloat
    /// How far the conversation is blurred while the reply view covers it.
    public var backdropBlurRadius: CGFloat

    public init(
        lineWidth: CGFloat = 4,
        color: Color = Color(white: 0.16),
        spineX: CGFloat = 15,
        stubEndX: CGFloat = 49,
        cornerRadius: CGFloat = 17.5,
        quoteStubDrop: CGFloat = 2,
        replyStubDrop: CGFloat = 3,
        clearance: CGFloat = 5,
        faceClearance: CGFloat = 1,
        loopBump: CGFloat = 2.33,
        loopRadius: CGFloat = 6.75,
        loopReach: CGFloat = 10,
        gapSameSide: CGFloat = 24,
        gapAcross: CGFloat = 12,
        gapBeforeName: CGFloat = 16,
        gapSameSideCounted: CGFloat = 27.33,
        gapAcrossCounted: CGFloat = 23.33,
        gapBeforeNameCounted: CGFloat = 23.33,
        quoteTopInset: CGFloat = 26,
        runEndGap: CGFloat = 34,
        faceSize: CGFloat = 20,
        faceOpacity: Double = 0.55,
        faceSpacing: CGFloat = 8,
        countSpacing: CGFloat = 8,
        countShiftBesideLine: CGFloat = 20,
        countTuckBeforeDate: CGFloat = 0,
        backdropBlurRadius: CGFloat = 0
    ) {
        self.lineWidth = lineWidth
        self.color = color
        self.spineX = spineX
        self.stubEndX = stubEndX
        self.cornerRadius = cornerRadius
        self.quoteStubDrop = quoteStubDrop
        self.replyStubDrop = replyStubDrop
        self.clearance = clearance
        self.faceClearance = faceClearance
        self.loopBump = loopBump
        self.loopRadius = loopRadius
        self.loopReach = loopReach
        self.gapSameSide = gapSameSide
        self.gapAcross = gapAcross
        self.gapBeforeName = gapBeforeName
        self.gapSameSideCounted = gapSameSideCounted
        self.gapAcrossCounted = gapAcrossCounted
        self.gapBeforeNameCounted = gapBeforeNameCounted
        self.quoteTopInset = quoteTopInset
        self.runEndGap = runEndGap
        self.faceSize = faceSize
        self.faceOpacity = faceOpacity
        self.faceSpacing = faceSpacing
        self.countSpacing = countSpacing
        self.countShiftBesideLine = countShiftBesideLine
        self.countTuckBeforeDate = countTuckBeforeDate
        self.backdropBlurRadius = backdropBlurRadius
    }

    /// From an original's bottom to the top of the row under it. `counted`: "N Replies"
    /// shows between the two.
    public func gap(quoteIsTrailing: Bool, replyIsTrailing: Bool, rowOpensWithName: Bool, counted: Bool) -> CGFloat {
        if rowOpensWithName {
            return counted ? gapBeforeNameCounted : gapBeforeName
        }
        if quoteIsTrailing == replyIsTrailing {
            return counted ? gapSameSideCounted : gapSameSide
        }
        return counted ? gapAcrossCounted : gapAcross
    }
}

// MARK: - Where the pieces of a row are

/// The pieces of a row the line is drawn between.
public enum ReplyAnchorRole: Hashable, Sendable {
    /// The original, above the first reply of a run.
    case quote
    /// The face of the original's sender.
    case quoteFace
    /// The row's own bubble.
    case bubble
    /// The face of the row's sender, where it shows.
    case replyFace
}

public struct ReplyAnchorKey: PreferenceKey {
    public static var defaultValue: [ReplyAnchorRole: Anchor<CGRect>] { [:] }

    public static func reduce(
        value: inout [ReplyAnchorRole: Anchor<CGRect>],
        nextValue: () -> [ReplyAnchorRole: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

public extension View {
    /// Tells the row's `ReplyThreadLine` where this piece is; nil reports nothing (a face
    /// that is laid out but not shown).
    func replyAnchor(_ role: ReplyAnchorRole?) -> some View {
        anchorPreference(key: ReplyAnchorKey.self, value: .bounds) { anchor in
            role.map { [$0: anchor] } ?? [:]
        }
    }
}

// MARK: - The line

/// What the thread line does in one row.
public struct ReplyLineInfo: Equatable, Sendable {
    public enum Side: Equatable, Sendable {
        case leading
        case trailing
    }

    /// The line arrives at the row's top edge: the row above is the original itself or an
    /// earlier reply of the same thread.
    public var entersFromAbove: Bool
    /// The line goes on through the row's bottom edge: the row under it is the next reply.
    public var leavesBelow: Bool
    /// The row's own bubble.
    public var bubble: Side
    /// The original drawn above the row, when the row opens a run away from its original.
    public var quote: Side?
    /// False for the original itself, with its replies right under it.
    public var isReply: Bool
    /// The next row of the run sits on the trailing side too: the line passes this bubble
    /// without a mark (only the last bubble of a sender's run carries the loop or the stub).
    public var nextIsTrailing: Bool

    public init(
        entersFromAbove: Bool,
        leavesBelow: Bool,
        bubble: Side,
        quote: Side? = nil,
        isReply: Bool = true,
        nextIsTrailing: Bool = false
    ) {
        self.entersFromAbove = entersFromAbove
        self.leavesBelow = leavesBelow
        self.bubble = bubble
        self.quote = quote
        self.isReply = isReply
        self.nextIsTrailing = nextIsTrailing
    }
}

/// Where a row's pieces are, in the row's own coordinates.
public struct ReplyLineGeometry: Equatable, Sendable {
    public var height: CGFloat
    public var bubble: CGRect
    public var face: CGRect?
    public var quote: CGRect?
    public var quoteFace: CGRect?

    public init(height: CGFloat, bubble: CGRect, face: CGRect? = nil, quote: CGRect? = nil, quoteFace: CGRect? = nil) {
        self.height = height
        self.bubble = bubble
        self.face = face
        self.quote = quote
        self.quoteFace = quoteFace
    }
}

/// The part of the thread line that lies in one row. Rows stand edge to edge, so a line that
/// leaves through the bottom edge meets the one that enters the next row at its top edge.
/// Before a reply on the leading side the two meet a clearance ABOVE that edge instead: the
/// room over such a bubble belongs to the row above (its bottom padding), so the row above
/// stops short and the reply's own row draws whatever lies between there and its bubble
/// (nothing, when the bubble opens the row; the stretch past a date line or a name otherwise).
public struct ReplyThreadLineShape: Shape {
    public var info: ReplyLineInfo
    public var geometry: ReplyLineGeometry
    public var style: ReplyStyle
    /// Centre of the vertical part and the end of a stub, from the row's leading edge.
    public var spineX: CGFloat
    public var stubEndX: CGFloat
    /// The chat shows faces: the line runs down their column, beside the bubbles.
    public var showsFaces: Bool

    public init(
        info: ReplyLineInfo,
        geometry: ReplyLineGeometry,
        style: ReplyStyle,
        spineX: CGFloat,
        stubEndX: CGFloat,
        showsFaces: Bool = false
    ) {
        self.info = info
        self.geometry = geometry
        self.style = style
        self.spineX = spineX
        self.stubEndX = stubEndX
        self.showsFaces = showsFaces
    }

    /// What the row's own bubble does to the line.
    private enum Ending {
        /// A reply on the leading side: the line stops above it.
        case stop(CGFloat)
        /// The last reply of the run, on the trailing side: a stub points at it.
        case stub(CGFloat)
        /// A reply on the trailing side with more of the run under it: a loop beside it.
        case loop(CGFloat)
        /// Straight on through the bottom edge.
        case through
    }

    private var ending: Ending {
        // The stroke's round ends reach half the line's width past the path.
        let cap = style.lineWidth / 2
        guard info.isReply else { return .through }
        if info.bubble == .leading {
            // Inside a sender's run in a chat with faces the line runs on down the faces'
            // column, to the face under the run's last bubble.
            if showsFaces, geometry.face == nil, info.leavesBelow {
                return .through
            }
            return .stop((geometry.face?.minY ?? geometry.bubble.minY) - style.clearance - cap)
        }
        guard info.leavesBelow else { return .stub(geometry.bubble.midY + style.replyStubDrop) }
        return info.nextIsTrailing ? .through : .loop(geometry.bubble.midY)
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let cap = style.lineWidth / 2
        let stubX = stubEndX - cap
        let reach = max(0, stubX - spineX)
        // Where the line hands over to the next row, and where this row takes it over.
        let handOver = style.clearance + cap
        let bottom = geometry.height - (info.leavesBelow && !info.nextIsTrailing ? handOver : 0)
        let ending = self.ending

        // The first height the vertical part has to reach; a turn may use the room up to it.
        let firstTarget: CGFloat
        var endsWithStub = false
        switch ending {
        case .stop(let y):
            firstTarget = y
        case .stub(let y):
            firstTarget = y
            endsWithStub = true
        case .loop(let y):
            firstTarget = y - style.loopReach
        case .through:
            firstTarget = bottom
        }

        // 1. Where the line begins.
        var y: CGFloat = 0
        if info.entersFromAbove {
            y = info.bubble == .leading ? -handOver : 0
            path.move(to: CGPoint(x: spineX, y: y))
        } else {
            // The block the line starts at: the original above the row, or the row's own
            // bubble when the row is the original.
            let block: CGRect
            let face: CGRect?
            let side: ReplyLineInfo.Side
            let underFace: CGFloat
            if let quoteSide = info.quote, let quote = geometry.quote {
                block = quote
                face = geometry.quoteFace
                side = quoteSide
                underFace = style.faceClearance
            } else if !info.isReply, info.leavesBelow {
                block = geometry.bubble
                face = geometry.face
                side = info.bubble
                underFace = style.clearance
            } else {
                return path
            }
            switch side {
            case .leading:
                y = (face.map { $0.maxY + underFace } ?? block.maxY + style.clearance) + cap
                path.move(to: CGPoint(x: spineX, y: y))
            case .trailing:
                let stubY = block.midY + style.quoteStubDrop
                let room = firstTarget - stubY
                guard room > 0 else { return path }
                let radius = min(style.cornerRadius, reach, endsWithStub ? room / 2 : room)
                path.move(to: CGPoint(x: stubX, y: stubY))
                path.addLine(to: CGPoint(x: spineX + radius, y: stubY))
                path.addArc(
                    center: CGPoint(x: spineX + radius, y: stubY + radius),
                    radius: radius,
                    startAngle: .degrees(270),
                    endAngle: .degrees(180),
                    clockwise: true
                )
                y = stubY + radius
            }
        }

        // 2. Down to the row's own bubble, and on.
        switch ending {
        case .through:
            path.addLine(to: CGPoint(x: spineX, y: max(y, bottom)))

        case .stop(let stop):
            if stop > y {
                path.addLine(to: CGPoint(x: spineX, y: stop))
            }
            if info.leavesBelow {
                let resume = (geometry.face?.maxY ?? geometry.bubble.maxY) + style.clearance + cap
                if resume < bottom {
                    path.move(to: CGPoint(x: spineX, y: resume))
                    path.addLine(to: CGPoint(x: spineX, y: bottom))
                }
            }

        case .stub(let stubY):
            let radius = min(style.cornerRadius, reach, max(0, stubY - y))
            path.addLine(to: CGPoint(x: spineX, y: stubY - radius))
            path.addArc(
                center: CGPoint(x: spineX + radius, y: stubY - radius),
                radius: radius,
                startAngle: .degrees(180),
                endAngle: .degrees(90),
                clockwise: true
            )
            path.addLine(to: CGPoint(x: stubX, y: stubY))

        case .loop(let middle):
            // The line leans toward the bubble and back, upright where it starts, at the
            // bubble's middle (where it meets the ring) and where it ends.
            let top = max(y, middle - style.loopReach)
            let low = min(bottom, middle + style.loopReach)
            let lean = spineX + style.loopBump
            path.addLine(to: CGPoint(x: spineX, y: top))
            path.addCurve(
                to: CGPoint(x: lean, y: middle),
                control1: CGPoint(x: spineX, y: (top + middle) / 2),
                control2: CGPoint(x: lean, y: (top + middle) / 2)
            )
            path.addCurve(
                to: CGPoint(x: spineX, y: low),
                control1: CGPoint(x: lean, y: (middle + low) / 2),
                control2: CGPoint(x: spineX, y: (middle + low) / 2)
            )
            path.addLine(to: CGPoint(x: spineX, y: bottom))
            path.addEllipse(in: CGRect(
                x: lean,
                y: middle - style.loopRadius,
                width: style.loopRadius * 2,
                height: style.loopRadius * 2
            ))
        }
        return path
    }
}

/// Draws the thread line over one whole row of the list (the date line a row opens with
/// included: the line runs past it). The row's pieces report where they are with
/// `replyAnchor`; a row outside any run (`info` nil) draws nothing.
public struct ReplyThreadLine: ViewModifier {
    var info: ReplyLineInfo?
    var style: ReplyStyle
    /// The row's own horizontal padding.
    var rowPadding: CGFloat
    /// Width of the faces' column in a chat that shows faces, nil in one that does not.
    var faceColumnWidth: CGFloat?
    /// How far the row's bubbles are slid aside (the list's drag that shows the times): the
    /// line goes with them.
    var slide: CGFloat

    public init(
        info: ReplyLineInfo?,
        style: ReplyStyle,
        rowPadding: CGFloat,
        faceColumnWidth: CGFloat? = nil,
        slide: CGFloat = 0
    ) {
        self.info = info
        self.style = style
        self.rowPadding = rowPadding
        self.faceColumnWidth = faceColumnWidth
        self.slide = slide
    }

    public func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(ReplyAnchorKey.self) { anchors in
                if let info, let bubble = anchors[.bubble] {
                    GeometryReader { proxy in
                        ReplyThreadLineShape(
                            info: info,
                            geometry: ReplyLineGeometry(
                                height: proxy.size.height,
                                bubble: proxy[bubble],
                                face: anchors[.replyFace].map { proxy[$0] },
                                quote: anchors[.quote].map { proxy[$0] },
                                quoteFace: anchors[.quoteFace].map { proxy[$0] }
                            ),
                            style: style,
                            spineX: rowPadding + (faceColumnWidth.map { $0 / 2 } ?? style.spineX),
                            stubEndX: rowPadding + style.stubEndX,
                            showsFaces: faceColumnWidth != nil
                        )
                        .stroke(
                            style.color,
                            style: StrokeStyle(lineWidth: style.lineWidth, lineCap: .round, lineJoin: .round)
                        )
                    }
                    .offset(x: slide)
                    .allowsHitTesting(false)
                }
            }
            // The row has read its pieces: the list above does not gather every row's.
            .preference(key: ReplyAnchorKey.self, value: [:])
    }
}

// MARK: - "N Replies" under a block

public extension View {
    /// Seats "N Replies" under this block without giving it room in the layout: the row that
    /// follows is placed by the reply's own gaps (`ReplyStyle.gap`), not by the label's height.
    func replyCountSeat<Label: View>(
        isShown: Bool,
        isTrailing: Bool,
        spacing: CGFloat,
        shift: CGFloat,
        @ViewBuilder label: () -> Label
    ) -> some View {
        // `overlay(_:alignment:)`: the library still builds for iOS 14.
        overlay(
            ReplyCountSeatAnchor(isShown: isShown, isTrailing: isTrailing, spacing: spacing, shift: shift, label: label()),
            alignment: isTrailing ? .bottomTrailing : .bottomLeading
        )
    }
}

/// A point at the block's bottom corner that carries the label, top to the corner (an
/// alignment guide on the label itself is lost in an overlay's own stack).
private struct ReplyCountSeatAnchor<Label: View>: View {
    @Environment(\.sizeCategory) private var sizeCategory

    var isShown: Bool
    var isTrailing: Bool
    var spacing: CGFloat
    var shift: CGFloat
    var label: Label

    var body: some View {
        if isShown {
            Color.clear
                .frame(width: 0, height: 0)
                .overlay(
                    label
                        // No room of its own: it stops growing with the text size where it
                        // would reach the reply under it.
                        .environment(\.sizeCategory, sizeCategory > .extraLarge ? .extraLarge : sizeCategory)
                        .fixedSize()
                        .padding(isTrailing ? .trailing : .leading, shift)
                        .offset(y: spacing),
                    alignment: isTrailing ? .topTrailing : .topLeading
                )
        }
    }
}

/// `replyCountSeat` as a modifier, for a body that is already long.
public struct ReplyCountSeat<Label: View>: ViewModifier {
    var isShown: Bool
    var isTrailing: Bool
    var spacing: CGFloat
    var shift: CGFloat
    var label: Label

    public init(isShown: Bool, isTrailing: Bool, spacing: CGFloat, shift: CGFloat, label: Label) {
        self.isShown = isShown
        self.isTrailing = isTrailing
        self.spacing = spacing
        self.shift = shift
        self.label = label
    }

    public func body(content: Content) -> some View {
        content.replyCountSeat(isShown: isShown, isTrailing: isTrailing, spacing: spacing, shift: shift) {
            label
        }
    }
}

// MARK: - The original above a run

/// The first reply of a run that stands away from its original: the original (`quote`) on
/// its sender's side, "N Replies" under it when the thread has more than one, and the row
/// itself (`row`) under that. The line is the row's (`ReplyThreadLine`); `row` marks its
/// bubble with `.replyAnchor(.bubble)` and, where it shows, its sender's face with
/// `.replyAnchor(.replyFace)`.
public struct ReplyContextStack<Quote: View, Face: View, Count: View, Row: View>: View {
    var style: ReplyStyle
    /// The original sits on the trailing side: the viewer wrote it.
    var quoteIsTrailing: Bool
    /// The reply sits on the trailing side: the viewer wrote it.
    var replyIsTrailing: Bool
    /// The row's own horizontal padding; the original takes the same.
    var rowPadding: CGFloat
    /// Width of the faces' column in a chat that shows faces, nil in one that does not.
    var faceColumnWidth: CGFloat?
    /// The row opens with its sender's name (a group chat).
    var rowOpensWithName: Bool
    /// "N Replies" shows under the original.
    var showsCount: Bool
    /// The row before this one is a message, not a date line.
    var followsMessage: Bool
    var quote: Quote
    var face: Face
    var count: Count
    var row: Row

    public init(
        style: ReplyStyle,
        quoteIsTrailing: Bool,
        replyIsTrailing: Bool,
        rowPadding: CGFloat,
        faceColumnWidth: CGFloat? = nil,
        rowOpensWithName: Bool = false,
        showsCount: Bool = false,
        followsMessage: Bool = false,
        @ViewBuilder quote: () -> Quote,
        @ViewBuilder face: () -> Face,
        @ViewBuilder count: () -> Count,
        @ViewBuilder row: () -> Row
    ) {
        self.style = style
        self.quoteIsTrailing = quoteIsTrailing
        self.replyIsTrailing = replyIsTrailing
        self.rowPadding = rowPadding
        self.faceColumnWidth = faceColumnWidth
        self.rowOpensWithName = rowOpensWithName
        self.showsCount = showsCount
        self.followsMessage = followsMessage
        self.quote = quote()
        self.face = face()
        self.count = count()
        self.row = row()
    }

    /// Without faces the line runs right under the original's leading edge, where the label
    /// would stand; with faces it runs down their column, clear of it.
    private var countShift: CGFloat {
        !quoteIsTrailing && faceColumnWidth == nil ? style.countShiftBesideLine : 0
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: style.faceSpacing) {
                if quoteIsTrailing {
                    Spacer(minLength: 0)
                } else if let faceColumnWidth {
                    face
                        .frame(width: style.faceSize, height: style.faceSize)
                        .opacity(style.faceOpacity)
                        .replyAnchor(.quoteFace)
                        .frame(width: faceColumnWidth)
                }
                quote
                    .replyAnchor(.quote)
                    .replyCountSeat(
                        isShown: showsCount,
                        isTrailing: quoteIsTrailing,
                        spacing: style.countSpacing,
                        shift: countShift
                    ) {
                        count
                    }
                if !quoteIsTrailing {
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, rowPadding)
            .padding(.top, followsMessage ? style.quoteTopInset : 0)
            .padding(.bottom, style.gap(
                quoteIsTrailing: quoteIsTrailing,
                replyIsTrailing: replyIsTrailing,
                rowOpensWithName: rowOpensWithName,
                counted: showsCount
            ))
            row
        }
    }
}
