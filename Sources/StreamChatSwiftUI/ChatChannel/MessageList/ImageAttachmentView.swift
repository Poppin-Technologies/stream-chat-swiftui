//
// Copyright © 2024 Stream.io Inc. All rights reserved.
//

import StreamChat
import SwiftUI

public struct ImageAttachmentContainer<Factory: ViewFactory>: View {
    @Injected(\.colors) private var colors
    @Injected(\.fonts) private var fonts
    @Injected(\.utils) private var utils
    @Injected(\.chatClient) private var chatClient

    /// Poppin: what Reply in the photo viewer does; nil where a reply cannot start.
    @Environment(\.photoViewerReply) private var photoViewerReply

    var factory: Factory
    let message: ChatMessage
    let width: CGFloat
    let isFirst: Bool
    @Binding var scrolledId: String?

    /// The open viewer: which photo it starts on, and whether it starts as the grid.
    @State private var viewer: PhotoViewerStart?
    @State private var replyAfterClose = false

    /// Poppin (2026-11-06): a live dm/group photo on the vanishing lifecycle carries
    /// `extraData["expiresAt"]`. The other person sees it sealed behind "Tap to view", and the
    /// view itself is what makes it disappear: closing the gallery reports `viewed`, the server
    /// tombstones the line and the `message.deleted` frame removes the row on both phones.
    private var isVanishing: Bool { message.extraData["expiresAt"] != nil }
    /// Opens once: the card, the one view, the report on closing.
    private var isSealed: Bool { message.mediaOpensOnce }
    /// Poppin (2026-11-21): a photo its sender marked No Screenshots shows to the other person
    /// only inside the covered viewer, so the list draws the card for it too. Without View Once
    /// it stays, and opens as often as they like.
    private var isCovered: Bool { message.mediaIsCovered }
    private var showsCard: Bool { message.mediaIsSealed }

    /// Poppin (2026-11-21): two or more photos draw as a stack with no bubble, like Messages.
    private var showsStack: Bool {
        guard #available(iOS 17.0, *) else { return false }
        return !showsCard && message.imageAttachments.count > 1
    }

    private var edge: HorizontalAlignment {
        message.isSentByCurrentUser ? .trailing : .leading
    }

    public var body: some View {
        // Poppin (2026-11-21): the sender's "Disappears" line stands under the bubble, not inside
        // its colour.
        VStack(alignment: edge, spacing: 0) {
            if showsStack {
                stackBody
            } else {
                bubbleBody
            }
            if message.isSentByCurrentUser, isVanishing || message.blocksScreenshots {
                VanishingMediaCaption(opensOnce: isVanishing, noScreenshots: message.blocksScreenshots)
            }
        }
        .fullScreenCover(item: $viewer, onDismiss: {
            if isSealed, let cid = message.cid {
                chatClient.reportMediaViewed(channelId: cid.id, messageId: message.id)
            }
            if replyAfterClose {
                replyAfterClose = false
                photoViewerReply?()
            }
        }) { start in
            GalleryView(
                imageAttachments: message.imageAttachments,
                author: message.author,
                isShown: Binding(
                    get: { viewer != nil },
                    set: { shown in
                        if !shown { viewer = nil }
                    }
                ),
                selected: start.index,
                startsInGrid: start.grid,
                isOneTimeView: isSealed,
                isProtected: isCovered,
                onReply: photoViewerReply == nil ? nil : {
                    replyAfterClose = true
                    viewer = nil
                }
            )
            .mediaCover(isCovered) { viewer = nil }
        }
        .accessibilityIdentifier("ImageAttachmentContainer")
    }

    private func open(_ index: Int, grid: Bool = false) {
        guard message.localState == nil else { return }
        viewer = PhotoViewerStart(index: index, grid: grid)
    }

    private var bubbleBody: some View {
        VStack(
            alignment: message.alignmentInBubble,
            spacing: 0
        ) {
            if let quotedMessage = utils.messageCachingUtils.quotedMessage(for: message) {
                factory.makeQuotedMessageView(
                    quotedMessage: quotedMessage,
                    fillAvailableSpace: !message.attachmentCounts.isEmpty,
                    isInComposer: false,
                    scrolledId: $scrolledId
                )
            }

            VStack(
                alignment: message.alignmentInBubble,
                spacing: 0
            ) {
                if showsCard {
                    VanishingMediaCard(kind: .photo, width: width, opensOnce: isSealed) {
                        open(0)
                    }
                } else {
                    ImageAttachmentView(
                        message: message,
                        width: width,
                        hugsShape: message.text.isEmpty && utils.messageCachingUtils.quotedMessage(for: message) == nil
                    ) { index in
                        open(index)
                    }
                    .transaction { transaction in
                      transaction.disablesAnimations = true
                      transaction.animation = nil
                    }
                }

                if !message.text.isEmpty {
                    AttachmentTextView(message: message, factory: factory)
                        .frame(width: width)
                }
            }
        }
        .modifier(
            factory.makeMessageViewModifier(
                for: MessageModifierInfo(
                    message: message, isFirst: isFirst && message.videoAttachments.isEmpty
                )
            )
        )
    }

    /// The stack has no bubble. A quote keeps its place above it and a caption gets a bubble of its
    /// own under it.
    @ViewBuilder
    private var stackBody: some View {
        if #available(iOS 17.0, *) {
            VStack(alignment: edge, spacing: 6) {
                if let quotedMessage = utils.messageCachingUtils.quotedMessage(for: message) {
                    factory.makeQuotedMessageView(
                        quotedMessage: quotedMessage,
                        fillAvailableSpace: false,
                        isInComposer: false,
                        scrolledId: $scrolledId
                    )
                    .modifier(
                        factory.makeMessageViewModifier(
                            for: MessageModifierInfo(message: message, isFirst: false)
                        )
                    )
                }

                PhotoStackView(
                    message: message,
                    width: width,
                    photoTapped: { index in open(index) },
                    gridTapped: { open(0, grid: true) }
                )

                if !message.text.isEmpty {
                    factory.makeMessageText(message: message)
                        .font(fonts.body)
                        .standardPadding()
                        .fixedSize(horizontal: false, vertical: true)
                        .modifier(
                            factory.makeMessageViewModifier(
                                for: MessageModifierInfo(message: message, isFirst: isFirst)
                            )
                        )
                }
            }
            .frame(maxWidth: width, alignment: Alignment(horizontal: edge, vertical: .center))
        }
    }
}

/// What the photo viewer opens on.
struct PhotoViewerStart: Identifiable {
    let id = UUID()
    let index: Int
    let grid: Bool
}

public struct AttachmentTextView<Factory: ViewFactory>: View {

    @Injected(\.colors) private var colors
    @Injected(\.fonts) private var fonts

    var message: ChatMessage
    var factory: Factory

    public init(message: ChatMessage, factory: Factory) {
        self.message = message
        self.factory = factory
    }

    public var body: some View {
        HStack {
          factory.makeMessageText(message: message)
                .font(fonts.body)
                .standardPadding()
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .background(Color(backgroundColor))
        .accessibilityIdentifier("AttachmentTextView")
    }

    private var backgroundColor: UIColor {
        var colors = colors
        if message.isSentByCurrentUser {
            if message.type == .ephemeral {
                return colors.background8
            } else {
                return colors.messageCurrentUserBackground[0]
            }
        } else {
            return colors.messageOtherUserBackground[0]
        }
    }
}

struct ImageAttachmentView: View {
    @Injected(\.colors) private var colors
    @Injected(\.fonts) private var fonts
    @Injected(\.utils) private var utils

    let message: ChatMessage
    let width: CGFloat
    /// Poppin (2026-11-21): one photo draws in its own shape (every photo was cut to 4:3), capped so a
    /// tall screenshot does not fill the screen. `false` keeps the bubble's full width: with a caption
    /// or a quote in the same bubble a narrower photo would leave the bubble's colour beside it.
    var hugsShape = false
    var imageTapped: ((Int) -> Void)? = nil

    private let spacing: CGFloat = 2
    private let maxDisplayedImages = 4

    private var singleSize: CGSize {
        guard let ratio = message.imageAttachments.first.flatMap({ PhotoShape.ratio(of: $0) }) else {
            return CGSize(width: width, height: fullHeight)
        }
        let fitted = PhotoShape.size(ratio: ratio, in: CGSize(width: width, height: (width * 1.25).rounded()))
        return hugsShape ? fitted : CGSize(width: width, height: fitted.height)
    }

    private var imageCDN: ImageCDN {
        utils.imageCDN
    }

    private var sources: [URL] {
        message.imageAttachments.map { attachment in
            if let state = attachment.uploadingState {
                return state.localFileURL
            } else {
                return attachment.imageURL
            }
        }
    }

    var body: some View {
        Group {
            if sources.count == 1 {
                SingleImageView(
                    source: sources[0],
                    width: singleSize.width,
                    height: singleSize.height,
                    imageTapped: imageTapped,
                    index: 0
                )
                .withUploadingStateIndicator(for: uploadState(for: 0), url: sources[0])
            } else if sources.count == 2 {
                HStack(spacing: spacing) {
                    MultiImageView(
                        source: sources[0],
                        width: width / 2,
                        height: fullHeight,
                        imageTapped: imageTapped,
                        index: 0
                    )
                    .withUploadingStateIndicator(for: uploadState(for: 0), url: sources[0])

                    MultiImageView(
                        source: sources[1],
                        width: width / 2,
                        height: fullHeight,
                        imageTapped: imageTapped,
                        index: 1
                    )
                    .withUploadingStateIndicator(for: uploadState(for: 1), url: sources[1])
                }
            } else if sources.count == 3 {
                HStack(spacing: spacing) {
                    MultiImageView(
                        source: sources[0],
                        width: width / 2,
                        height: fullHeight,
                        imageTapped: imageTapped,
                        index: 0
                    )
                    .withUploadingStateIndicator(for: uploadState(for: 0), url: sources[0])

                    VStack(spacing: spacing) {
                        MultiImageView(
                            source: sources[1],
                            width: width / 2,
                            height: fullHeight / 2,
                            imageTapped: imageTapped,
                            index: 1
                        )
                        .withUploadingStateIndicator(for: uploadState(for: 1), url: sources[1])

                        MultiImageView(
                            source: sources[2],
                            width: width / 2,
                            height: fullHeight / 2,
                            imageTapped: imageTapped,
                            index: 2
                        )
                        .withUploadingStateIndicator(for: uploadState(for: 2), url: sources[2])
                    }
                }
            } else if sources.count > 3 {
                HStack(spacing: spacing) {
                    VStack(spacing: spacing) {
                        MultiImageView(
                            source: sources[0],
                            width: width / 2,
                            height: fullHeight / 2,
                            imageTapped: imageTapped,
                            index: 0
                        )
                        .withUploadingStateIndicator(for: uploadState(for: 0), url: sources[0])

                        MultiImageView(
                            source: sources[2],
                            width: width / 2,
                            height: fullHeight / 2,
                            imageTapped: imageTapped,
                            index: 2
                        )
                        .withUploadingStateIndicator(for: uploadState(for: 2), url: sources[2])
                    }

                    VStack(spacing: spacing) {
                        MultiImageView(
                            source: sources[1],
                            width: width / 2,
                            height: fullHeight / 2,
                            imageTapped: imageTapped,
                            index: 1
                        )
                        .withUploadingStateIndicator(for: uploadState(for: 1), url: sources[1])

                        ZStack {
                            MultiImageView(
                                source: sources[3],
                                width: width / 2,
                                height: fullHeight / 2,
                                imageTapped: imageTapped,
                                index: 3
                            )
                            .withUploadingStateIndicator(for: uploadState(for: 3), url: sources[3])

                            if notDisplayedImages > 0 {
                                Color.black.opacity(0.4)
                                    .allowsHitTesting(false)

                                Text("+\(notDisplayedImages)")
                                    .foregroundColor(Color(colors.staticColorText))
                                    .font(fonts.title)
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(width: width / 2, height: fullHeight / 2)
                    }
                }
            }
        }
        .frame(
            width: sources.count == 1 ? singleSize.width : width,
            height: sources.count == 1 ? singleSize.height : fullHeight
        )
    }

    private var fullHeight: CGFloat {
        3 * width / 4
    }

    private var notDisplayedImages: Int {
        sources.count > maxDisplayedImages ? sources.count - maxDisplayedImages : 0
    }

    private func uploadState(for index: Int) -> AttachmentUploadingState? {
        message.imageAttachments[index].uploadingState
    }
}

struct SingleImageView: View {
    let source: URL
    let width: CGFloat
    let height: CGFloat
    var imageTapped: ((Int) -> Void)? = nil
    var index: Int?

    var body: some View {
        LazyLoadingImage(
            source: source,
            width: width,
            height: height,
            imageTapped: imageTapped,
            index: index
        )
        .frame(width: width, height: height)
        .accessibilityIdentifier("SingleImageView")
    }
}

struct MultiImageView: View {
    let source: URL
    let width: CGFloat
    let height: CGFloat
    var imageTapped: ((Int) -> Void)? = nil
    var index: Int?

    var body: some View {
        LazyLoadingImage(
            source: source,
            width: width,
            height: height,
            imageTapped: imageTapped,
            index: index
        )
        .frame(width: width, height: height)
        .accessibilityIdentifier("MultiImageView")
    }
}

struct LazyLoadingImage: View {
    @Injected(\.utils) private var utils

    @State private var image: UIImage?
    @State private var error: Error?

    let source: URL
    let width: CGFloat
    let height: CGFloat
    var resize: Bool = true
    var shouldSetFrame: Bool = true
    var imageTapped: ((Int) -> Void)? = nil
    var index: Int?
    var onImageLoaded: (UIImage) -> Void = { _ in /* Default implementation. */ }

    var body: some View {
        ZStack {
            if let image = image {
                imageView(for: image)
                if let imageTapped = imageTapped {
                    // NOTE: needed because of bug with SwiftUI.
                    // The click area expands outside the image view (although not visible).
                    Rectangle()
                        .opacity(0.000001)
                        .frame(width: width, height: height)
                        .clipped()
                        .allowsHitTesting(true)
                        .highPriorityGesture(
                            TapGesture()
                                .onEnded { _ in
                                    imageTapped(index ?? 0)
                                }
                        )
                }
            } else if error != nil {
                Color(.secondarySystemBackground)
            } else {
                ZStack {
                    Color(.secondarySystemBackground)
                    ProgressView()
                }
            }
        }
        .onAppear {
            if image != nil {
                return
            }

            utils.imageLoader.loadImage(
                url: source,
                imageCDN: utils.imageCDN,
                resize: resize,
                preferredSize: CGSize(width: width, height: height),
                completion: { result in
                    switch result {
                    case let .success(image):
                        self.image = image
                        onImageLoaded(image)
                    case let .failure(error):
                        self.error = error
                    }
                }
            )
        }
    }

    func imageView(for image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .aspectRatio(contentMode: .fill)
            .frame(width: shouldSetFrame ? width : nil, height: shouldSetFrame ? height : nil)
            .allowsHitTesting(false)
            .scaleEffect(1.0001) // Needed because of SwiftUI sometimes incorrectly displaying landscape images.
            .clipped()
    }
}

extension ChatMessage {

    var alignmentInBubble: HorizontalAlignment {
        .leading
    }
}
