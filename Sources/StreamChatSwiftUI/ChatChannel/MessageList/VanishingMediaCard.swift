//
// Poppin (2026-11-06): vanishing photos and videos in dm/group chats (backend contract §3.4).
//

import SwiftUI

/// The sealed card a live vanishing photo or video shows to the person who has not viewed it
/// yet — no preview, the media glyph, "Tap to view". Opening the viewer is the view; closing it
/// reports `viewed` and the line disappears for both people (per member in a group).
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
    let onTap: () -> Void

    init(kind: Kind, width: CGFloat, ratio: CGFloat = 0.75, cornerRadius: CGFloat = 24, onTap: @escaping () -> Void) {
        self.kind = kind
        self.width = width
        self.ratio = ratio
        self.cornerRadius = cornerRadius
        self.onTap = onTap
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: kind == .photo ? "photo.fill" : "video.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(colors.tintColor)
            Text("Tap to view")
                .font(fonts.footnoteBold)
                .foregroundColor(.primary)
            Text(kind == .photo ? "Photo · gone once you've seen it" : "Video · gone once you've seen it")
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

/// The sender's line under their own vanishing photo or video.
struct VanishingMediaCaption: View {
    @Injected(\.colors) private var colors
    @Injected(\.fonts) private var fonts

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")
                .font(.system(size: 10, weight: .semibold))
            Text("Disappears after it's viewed")
        }
        .font(fonts.caption1)
        .foregroundColor(Color(colors.textLowEmphasis))
        .padding(.top, 4)
        .accessibilityIdentifier("VanishingMediaCaption")
    }
}
