//
// Poppin (2026-11-06): vanishing photos and videos in dm/group chats (backend contract §3.4).
//

import SwiftUI

/// The sealed card a photo or video shows to the person it was sent to in place of the picture:
/// no preview, the media glyph, "Tap to view". A View Once one (`opensOnce`) is live on the
/// vanishing lifecycle: opening the viewer is the view, closing it reports `viewed` and the
/// line disappears for both people (per member in a group). A No Screenshots one that stays
/// (2026-11-21) opens as often as they like, inside the covered viewer.
struct VanishingMediaCard: View {
    @Injected(\.colors) private var colors
    @Injected(\.fonts) private var fonts

    enum Kind {
        case photo
        case video
    }

    let kind: Kind
    let width: CGFloat
    var ratio: CGFloat = 0.75
    var cornerRadius: CGFloat = 24
    var opensOnce: Bool = true
    let onTap: () -> Void

    init(kind: Kind, width: CGFloat, ratio: CGFloat = 0.75, cornerRadius: CGFloat = 24, opensOnce: Bool = true, onTap: @escaping () -> Void) {
        self.kind = kind
        self.width = width
        self.ratio = ratio
        self.cornerRadius = cornerRadius
        self.opensOnce = opensOnce
        self.onTap = onTap
    }

    private var subtitle: String {
        let what = kind == .photo ? "Photo" : "Video"
        return opensOnce ? "\(what) · gone once you've seen it" : "\(what) · no screenshots"
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: kind == .photo ? "photo.fill" : "video.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(colors.tintColor)
            Text("Tap to view")
                .font(fonts.footnoteBold)
                .foregroundColor(.primary)
            Text(subtitle)
                .font(fonts.caption1)
                .foregroundColor(Color(colors.textLowEmphasis))
                .multilineTextAlignment(.center)
        }
        .frame(width: width, height: width * ratio)
        .background(Color(colors.background1))
        .cornerRadius(cornerRadius)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityIdentifier("VanishingMediaCard")
    }
}

/// The sender's line under their own photo or video: what the other person can do with it.
struct VanishingMediaCaption: View {
    @Injected(\.colors) private var colors
    @Injected(\.fonts) private var fonts

    /// False for a photo that stays in the chat.
    var opensOnce: Bool
    /// The sender marked it No Screenshots (2026-11-21).
    var noScreenshots: Bool

    init(opensOnce: Bool = true, noScreenshots: Bool = false) {
        self.opensOnce = opensOnce
        self.noScreenshots = noScreenshots
    }

    private var line: String {
        switch (opensOnce, noScreenshots) {
        case (true, true): return "View once, no screenshots"
        case (true, false): return "Disappears after it's viewed"
        case (false, _): return "No screenshots"
        }
    }

    var body: some View {
        // Poppin (2026-11-21): it stands under the bubble on the sender's side, small and gray,
        // the way Messages writes "Delivered". Its callers place it outside the bubble's colour.
        HStack(spacing: 3) {
            Image(systemName: opensOnce ? "timer" : "eye.slash")
                .font(.system(size: 9, weight: .bold))
            Text(line)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(Color(colors.textLowEmphasis))
        .padding(.top, 4)
        .padding(.horizontal, 4)
        .accessibilityIdentifier("VanishingMediaCaption")
    }
}

/// The line an opened View Once photo or video leaves in its place, for both people (backend
/// contract §3.4 `opened`, 2026-11-21).
public struct OpenedMediaLine: View {
    @Injected(\.colors) private var colors

    let kind: String?

    public init(kind: String?) {
        self.kind = kind
    }

    public var body: some View {
        HStack(spacing: 5) {
            Image(systemName: kind == "video" ? "video" : "photo")
                .font(.system(size: 12, weight: .semibold))
            Text("Opened")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(Color(colors.textLowEmphasis))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .overlay(
            Capsule()
                .strokeBorder(Color(colors.textLowEmphasis).opacity(0.4), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind == "video" ? "Video, opened" : "Photo, opened")
        .accessibilityIdentifier("OpenedMediaLine")
    }
}
