//
//  ReplyContextStack.swift
//  Poppin: a reply row the way Apple Messages draws it (measured 2026-11-10 on a 430pt phone).
//
//  The original sits above the reply as its own block, on its sender's side, and a grey line
//  in the leading gutter joins the two. SwiftUI only: the chat proof harness
//  (scripts/ui-proof/chat-bubble-twin) compiles this file as it is.
//

import SwiftUI

/// The numbers of Messages' reply: the row, its line, and the reply view's backdrop. Distances
/// along x are measured from the row's padded leading edge (the list pads its rows by
/// `MessagePaddings.horizontal`).
public struct ReplyStyle {
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
    /// The line starts this far under an original on the leading side, and stops this far
    /// above a reply (or its sender's face) on the leading side.
    public var clearance: CGFloat
    /// The line starts this far under the face of the original's sender.
    public var faceClearance: CGFloat
    /// From the original's bottom to the reply's row: both on one side, on opposite sides,
    /// and when the row opens with its sender's name.
    public var gapSameSide: CGFloat
    public var gapAcross: CGFloat
    public var gapBeforeName: CGFloat
    /// The face of the original's sender, in a chat that shows faces.
    public var faceSize: CGFloat
    public var faceOpacity: Double
    public var faceSpacing: CGFloat
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
        gapSameSide: CGFloat = 24,
        gapAcross: CGFloat = 12,
        gapBeforeName: CGFloat = 16,
        faceSize: CGFloat = 20,
        faceOpacity: Double = 0.55,
        faceSpacing: CGFloat = 8,
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
        self.gapSameSide = gapSameSide
        self.gapAcross = gapAcross
        self.gapBeforeName = gapBeforeName
        self.faceSize = faceSize
        self.faceOpacity = faceOpacity
        self.faceSpacing = faceSpacing
        self.countTuckBeforeDate = countTuckBeforeDate
        self.backdropBlurRadius = backdropBlurRadius
    }
}

/// The pieces of a reply row the line is drawn between.
public enum ReplyAnchorRole: Hashable {
    /// The original, above the reply.
    case quote
    /// The face of the original's sender.
    case quoteFace
    /// The reply's own bubble.
    case bubble
    /// The face of the reply's sender.
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
    /// Tells an enclosing `ReplyContextStack` where this piece of the row is.
    func replyAnchor(_ role: ReplyAnchorRole) -> some View {
        anchorPreference(key: ReplyAnchorKey.self, value: .bounds) { [role: $0] }
    }
}

/// Where the line begins or ends: with a stub that points at a bubble on the trailing side,
/// or open, right under (or above) a block on the leading side.
public enum ReplyLineEnd: Equatable, Sendable {
    case stub(y: CGFloat)
    case open(y: CGFloat)

    var y: CGFloat {
        switch self {
        case .stub(let y), .open(let y): return y
        }
    }

    var isStub: Bool {
        if case .stub = self { return true }
        return false
    }
}

/// The line itself. `top` and `bottom` are where the line's INK begins and ends for an open
/// end, and the centre of the stub for a stub.
public struct ReplyLineShape: Shape {
    public var spineX: CGFloat
    public var stubEndX: CGFloat
    public var cornerRadius: CGFloat
    public var lineWidth: CGFloat
    public var top: ReplyLineEnd
    public var bottom: ReplyLineEnd

    public init(
        spineX: CGFloat,
        stubEndX: CGFloat,
        cornerRadius: CGFloat,
        lineWidth: CGFloat,
        top: ReplyLineEnd,
        bottom: ReplyLineEnd
    ) {
        self.spineX = spineX
        self.stubEndX = stubEndX
        self.cornerRadius = cornerRadius
        self.lineWidth = lineWidth
        self.top = top
        self.bottom = bottom
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        // The stroke's round ends reach half the line's width past the path.
        let cap = lineWidth / 2
        let startY = top.isStub ? top.y : top.y + cap
        let endY = bottom.isStub ? bottom.y : bottom.y - cap
        let turns: CGFloat = (top.isStub ? 1 : 0) + (bottom.isStub ? 1 : 0)
        guard endY > startY else { return path }
        let radius = turns == 0 ? 0 : min(cornerRadius, (endY - startY) / turns, max(0, stubEndX - cap - spineX))
        let stubX = stubEndX - cap

        if top.isStub {
            path.move(to: CGPoint(x: stubX, y: startY))
            path.addLine(to: CGPoint(x: spineX + radius, y: startY))
            path.addArc(
                center: CGPoint(x: spineX + radius, y: startY + radius),
                radius: radius,
                startAngle: .degrees(270),
                endAngle: .degrees(180),
                clockwise: true
            )
        } else {
            path.move(to: CGPoint(x: spineX, y: startY))
        }
        if bottom.isStub {
            path.addLine(to: CGPoint(x: spineX, y: endY - radius))
            path.addArc(
                center: CGPoint(x: spineX + radius, y: endY - radius),
                radius: radius,
                startAngle: .degrees(180),
                endAngle: .degrees(90),
                clockwise: true
            )
            path.addLine(to: CGPoint(x: stubX, y: endY))
        } else {
            path.addLine(to: CGPoint(x: spineX, y: endY))
        }
        return path
    }
}

/// A reply row: the original (`quote`) on its sender's side, the row itself (`row`) under it,
/// and the line between them. `row` marks its bubble with `.replyAnchor(.bubble)` and, where
/// faces show, its sender's face with `.replyAnchor(.replyFace)`.
public struct ReplyContextStack<Quote: View, Face: View, Row: View>: View {
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
    var quote: Quote
    var face: Face
    var row: Row

    public init(
        style: ReplyStyle,
        quoteIsTrailing: Bool,
        replyIsTrailing: Bool,
        rowPadding: CGFloat,
        faceColumnWidth: CGFloat? = nil,
        rowOpensWithName: Bool = false,
        @ViewBuilder quote: () -> Quote,
        @ViewBuilder face: () -> Face,
        @ViewBuilder row: () -> Row
    ) {
        self.style = style
        self.quoteIsTrailing = quoteIsTrailing
        self.replyIsTrailing = replyIsTrailing
        self.rowPadding = rowPadding
        self.faceColumnWidth = faceColumnWidth
        self.rowOpensWithName = rowOpensWithName
        self.quote = quote()
        self.face = face()
        self.row = row()
    }

    private var gap: CGFloat {
        if rowOpensWithName { return style.gapBeforeName }
        return quoteIsTrailing == replyIsTrailing ? style.gapSameSide : style.gapAcross
    }

    private var spineX: CGFloat {
        rowPadding + (faceColumnWidth.map { $0 / 2 } ?? style.spineX)
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
                if !quoteIsTrailing {
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, rowPadding)
            .padding(.bottom, gap)
            row
        }
        .overlayPreferenceValue(ReplyAnchorKey.self) { anchors in
            GeometryReader { proxy in
                line(anchors: anchors, proxy: proxy)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func line(anchors: [ReplyAnchorRole: Anchor<CGRect>], proxy: GeometryProxy) -> some View {
        if let quoteAnchor = anchors[.quote], let bubbleAnchor = anchors[.bubble] {
            let quoteRect = proxy[quoteAnchor]
            let bubbleRect = proxy[bubbleAnchor]
            let top: ReplyLineEnd = quoteIsTrailing
                ? .stub(y: quoteRect.midY + style.quoteStubDrop)
                : .open(y: anchors[.quoteFace].map { proxy[$0].maxY + style.faceClearance } ?? quoteRect.maxY + style.clearance)
            let bottom: ReplyLineEnd = replyIsTrailing
                ? .stub(y: bubbleRect.midY + style.replyStubDrop)
                : .open(y: (anchors[.replyFace].map { proxy[$0].minY } ?? bubbleRect.minY) - style.clearance)
            ReplyLineShape(
                spineX: spineX,
                stubEndX: rowPadding + style.stubEndX,
                cornerRadius: style.cornerRadius,
                lineWidth: style.lineWidth,
                top: top,
                bottom: bottom
            )
            .stroke(style.color, style: StrokeStyle(lineWidth: style.lineWidth, lineCap: .round, lineJoin: .round))
        }
    }
}
