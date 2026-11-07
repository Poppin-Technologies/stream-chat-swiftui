//
// Copyright © 2024 Stream.io Inc. All rights reserved.
//

import AVKit
import StreamChat
import SwiftUI

public struct VideoAttachmentsContainer<Factory: ViewFactory>: View {

    @Injected(\.utils) private var utils

    var factory: Factory
    let message: ChatMessage
    let width: CGFloat
    @Binding var scrolledId: String?

    public var body: some View {
        VStack(spacing: 0) {
            if let quotedMessage = utils.messageCachingUtils.quotedMessage(for: message) {
                VStack {
                    factory.makeQuotedMessageView(
                        quotedMessage: quotedMessage,
                        fillAvailableSpace: !message.attachmentCounts.isEmpty,
                        isInComposer: false,
                        scrolledId: $scrolledId
                    )

                    VideoAttachmentsList(
                        message: message,
                        width: width
                    )
                }
                .modifier(
                    factory.makeMessageViewModifier(
                        for: MessageModifierInfo(
                            message: message,
                            isFirst: false
                        )
                    )
                )
            } else {
                VideoAttachmentsList(
                    message: message,
                    width: width
                )
            }

            if !message.text.isEmpty {
                AttachmentTextView(message: message, factory: factory)
                    .frame(width: width)
            }
        }
        .if(!message.text.isEmpty, transform: { view in
            view.modifier(
                factory.makeMessageViewModifier(
                    for: MessageModifierInfo(
                        message: message,
                        isFirst: true,
                        cornerRadius: 24
                    )
                )
            )
        })
        .accessibilityIdentifier("VideoAttachmentsContainer")
    }
}

public struct VideoAttachmentsList: View {

    let message: ChatMessage
    let width: CGFloat

    public init(message: ChatMessage, width: CGFloat) {
        self.message = message
        self.width = width
    }

    public var body: some View {
        VStack {
            ForEach(message.videoAttachments, id: \.self) { attachment in
                VideoAttachmentView(
                    attachment: attachment,
                    message: message,
                    width: width
                )
                .withUploadingStateIndicator(
                    for: attachment.uploadingState,
                    url: attachment.videoURL
                )
            }
            if message.extraData["expiresAt"] != nil && message.isSentByCurrentUser {
                VanishingMediaCaption()
            }
        }
    }
}

public struct VideoAttachmentView: View {
    @Injected(\.chatClient) private var chatClient


    let attachment: ChatMessageVideoAttachment
    let message: ChatMessage
    let width: CGFloat
    var ratio: CGFloat = 0.75
    var cornerRadius: CGFloat = 24

    /// Poppin (2026-11-06): a live dm/group video on the vanishing lifecycle is sealed for the
    /// other person until they open it; closing the player reports `viewed` (see
    /// ImageAttachmentContainer for the photo twin).
    private var isSealed: Bool { message.extraData["expiresAt"] != nil && !message.isSentByCurrentUser }

    public init(
        attachment: ChatMessageVideoAttachment,
        message: ChatMessage,
        width: CGFloat,
        ratio: CGFloat = 0.75,
        cornerRadius: CGFloat = 24
    ) {
        self.attachment = attachment
        self.message = message
        self.width = width
        self.ratio = ratio
        self.cornerRadius = cornerRadius
    }

    @State var previewImage: UIImage?
    @State var error: Error?
    @State var fullScreenShown = false

    public var body: some View {
        VideoAttachmentContentView(
            attachment: attachment,
            author: message.author,
            width: width,
            ratio: ratio,
            cornerRadius: cornerRadius,
            sealed: isSealed,
            onViewerClosed: {
                if isSealed, let cid = message.cid {
                    chatClient.reportMediaViewed(channelId: cid.id, messageId: message.id)
                }
            }
        )
        .accessibilityIdentifier("VideoAttachmentView")
    }
}

public struct VideoAttachmentContentView: View {

    @Injected(\.utils) private var utils
    @Injected(\.images) private var images

    private var videoPreviewLoader: VideoPreviewLoader {
        utils.videoPreviewLoader
    }

    public let attachment: ChatMessageVideoAttachment
    public let author: ChatUser
    public let width: CGFloat
    public var ratio: CGFloat = 0.75
    public var cornerRadius: CGFloat = 24
    /// Poppin (2026-11-06): a sealed vanishing video draws the "Tap to view" card instead of
    /// its poster; `onViewerClosed` fires when the full-screen player is dismissed.
    public var sealed: Bool = false
    public var onViewerClosed: (() -> Void)? = nil
  
  
    public init(
        attachment: ChatMessageVideoAttachment,
        author: ChatUser,
        width: CGFloat,
        ratio: CGFloat,
        cornerRadius: CGFloat,
        sealed: Bool = false,
        onViewerClosed: (() -> Void)? = nil
    ) {
      self.attachment = attachment
      self.author = author
      self.width = width
      self.ratio = ratio
      self.cornerRadius = cornerRadius
      self.sealed = sealed
      self.onViewerClosed = onViewerClosed
    }

    @State var previewImage: UIImage?
    @State var error: Error?
    @State var fullScreenShown = false

    public var body: some View {
        Group {
            if sealed {
                VanishingMediaCard(kind: .video, width: width, ratio: ratio, cornerRadius: cornerRadius) {
                    fullScreenShown = true
                }
            } else {
                videoPreview
            }
        }
        .fullScreenCover(isPresented: $fullScreenShown, onDismiss: {
            onViewerClosed?()
        }) {
            VideoPlayerView(
                attachment: attachment,
                author: author,
                isShown: $fullScreenShown
            )
        }
        .onAppear {
            guard !sealed else { return } // nothing to preview behind the seal
            videoPreviewLoader.loadPreviewForVideo(at: attachment.videoURL) { result in
                switch result {
                case let .success(image):
                    self.previewImage = image
                case let .failure(error):
                    self.error = error
                }
            }
        }
    }

    private var videoPreview: some View {
        ZStack {
            if let previewImage = previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .clipped()
                    .allowsHitTesting(false)

                if width > 64 && attachment.uploadingState == nil {
                    VStack {
                        Image(uiImage: images.playFilled)
                            .customizable()
                            .frame(width: 24)
                            .foregroundColor(.white)
                            .modifier(ShadowModifier())
                    }
                    .frame(width: width, height: width * ratio)
                    .contentShape(Rectangle())
                    .clipped()
                    .onTapGesture {
                        fullScreenShown = true
                    }
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
        .frame(width: width, height: width * ratio)
        .cornerRadius(cornerRadius)
    }
}
