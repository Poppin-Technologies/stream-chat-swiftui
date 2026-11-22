//
// Poppin (2026-11-21): View Once and No Screenshots (backend contract §3.4 / §3.5).
//

import StreamChat
import SwiftUI

/// What the fork asks the app about a photo or a video in a chat. The app answers once, where it
/// sets the fork up (`initStreamUI`), so no chat screen and no view factory has to know.
public enum ChatMediaProtection {
    /// Whether this build offers the sender the two choices: the app's own switch. The server's
    /// feature is asked on top of it (`isOffered(by:)`).
    public static var appOffers: () -> Bool = { false }

    /// Wraps the full-screen viewer of a photo or a video marked No Screenshots, so that a
    /// screenshot, a recording and a screen share show nothing of it. The second value closes
    /// the viewer, for a cover that takes the touches. As it stands the viewer is shown as it
    /// is: the app supplies its screenshot shield.
    public static var cover: (AnyView, @escaping () -> Void) -> AnyView = { viewer, _ in viewer }

    /// The name a server gives the feature in `hello.features`.
    public static let serverFeature = "viewOnce"

    /// The choices are offered: the app's switch is on and the server takes them.
    public static func isOffered(by client: ChatClient) -> Bool {
        appOffers() && client.serverFeatures.contains(serverFeature)
    }

    /// How wide the app's two choice buttons stand beside the send arrow. The app draws them,
    /// so it says; the field's words keep clear of that much while the buttons show.
    public static var choiceButtonsWidth: CGFloat = 0
}

public extension ChatMessage {
    /// Another person's photo or video that opens once and is gone (the vanishing lifecycle).
    var mediaOpensOnce: Bool { extraData["expiresAt"] != nil && !isSentByCurrentUser }

    /// Another person's photo or video marked No Screenshots: shown only in the covered viewer.
    var mediaIsCovered: Bool { blocksScreenshots && !isSentByCurrentUser }

    /// Either: a message list draws the "Tap to view" card in its place, never the picture.
    var mediaIsSealed: Bool { mediaOpensOnce || mediaIsCovered }
}

extension View {
    /// The viewer as it is, or inside the app's cover when the media it shows is covered.
    @ViewBuilder
    func mediaCover(_ covered: Bool, close: @escaping () -> Void) -> some View {
        if covered {
            ChatMediaProtection.cover(AnyView(self), close)
        } else {
            self
        }
    }
}

/// The sealed card of another person's View Once or No Screenshots photo, whole: the card, the
/// viewer it opens, and the report that a View Once photo was seen. For a row the fork does not
/// draw itself (the event chat's own rows in the app).
public struct SealedPhotoCard: View {
    @Injected(\.chatClient) private var chatClient

    let message: ChatMessage
    let width: CGFloat
    @State private var viewerShown = false

    public init(message: ChatMessage, width: CGFloat) {
        self.message = message
        self.width = width
    }

    public var body: some View {
        VanishingMediaCard(kind: .photo, width: width, opensOnce: message.mediaOpensOnce) {
            viewerShown = true
        }
        .fullScreenCover(isPresented: $viewerShown, onDismiss: {
            if message.mediaOpensOnce, let cid = message.cid {
                chatClient.reportMediaViewed(channelId: cid.id, messageId: message.id)
            }
        }) {
            GalleryView(
                imageAttachments: message.imageAttachments,
                author: message.author,
                isShown: $viewerShown,
                selected: 0,
                startsInGrid: false,
                isOneTimeView: message.mediaOpensOnce,
                isProtected: message.mediaIsCovered,
                onReply: nil
            )
            .mediaCover(message.mediaIsCovered) { viewerShown = false }
        }
    }
}

/// One line over the field while a choice is on: what this send does with its photos and videos.
struct MediaChoiceLine: View {
    @Injected(\.colors) private var colors

    @ObservedObject var viewModel: MessageComposerViewModel

    init(viewModel: MessageComposerViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        if let line {
            Text(line)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(colors.textLowEmphasis))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 16)
                .padding(.bottom, 2)
                .accessibilityIdentifier("MediaChoiceLine")
        }
    }

    private var line: String? {
        guard viewModel.offersMediaChoices else { return nil }
        switch (viewModel.viewOnceChosen, viewModel.noScreenshotsChosen) {
        case (true, true): return "Opens once. No screenshots."
        case (true, false): return "Opens once. Screenshots allowed."
        case (false, true): return "Stays in the chat. No screenshots."
        case (false, false): return nil
        }
    }
}
