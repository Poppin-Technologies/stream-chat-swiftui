//
// Copyright © 2024 Stream.io Inc. All rights reserved.
//

import Foundation
import StreamChat
import SwiftUI

/// View model for the `MediaAttachmentsView`.
public class MediaAttachmentsViewModel: ObservableObject {

    @Published public var mediaItems = [MediaItem]()
    @Published public var loading = false
    @Published public var galleryShown = false

    @Injected(\.chatClient) var chatClient

    private let channel: ChatChannel
    private var messageSearchController: ChatMessageSearchController!

    private var loadingNextMessages = false

    public var allImageAttachments: [ChatMessageImageAttachment] {
        mediaItems.compactMap(\.imageAttachment)
    }

    public init(channel: ChatChannel) {
        self.channel = channel
        messageSearchController = chatClient.messageSearchController()
        loadMessages()
    }

    public init(
        channel: ChatChannel,
        messageSearchController: ChatMessageSearchController
    ) {
        self.channel = channel
        self.messageSearchController = messageSearchController
        loadMessages()
    }

    func onMediaAttachmentAppear(with index: Int) {
        if index < mediaItems.count - 10 {
            return
        }

        if !loadingNextMessages {
            loadingNextMessages = true
            messageSearchController.loadNextMessages { [weak self] _ in
                guard let self = self else { return }
                self.updateAttachments()
                self.loadingNextMessages = false
            }
        }
    }

    private func loadMessages() {
        let query = MessageSearchQuery(
            channelFilter: .equal(.cid, to: channel.cid),
            messageFilter: .withAttachments([.image, .video])
        )

        loading = true
        messageSearchController.search(query: query, completion: { [weak self] _ in
            guard let self = self else { return }
            self.updateAttachments()
            self.loading = false
        })
    }

    private func updateAttachments() {
        var result = [MediaItem]()
        for message in messageSearchController.messages {
            let imageAttachments = message.imageAttachments
            let videoAttachments = message.videoAttachments
            for imageAttachment in imageAttachments {
                let mediaItem = MediaItem(
                    id: imageAttachment.id.rawValue,
                    isVideo: false,
                    author: message.author,
                    videoAttachment: nil,
                    imageAttachment: imageAttachment
                )
                result.append(mediaItem)
            }
            for videoAttachment in videoAttachments {
                let mediaItem = MediaItem(
                    id: videoAttachment.id.rawValue,
                    isVideo: true,
                    author: message.author,
                    videoAttachment: videoAttachment,
                    imageAttachment: nil
                )
                result.append(mediaItem)
            }
        }
        withAnimation {
            self.mediaItems = result
        }
    }
}

public struct MediaItem: Identifiable {
    public let id: String
    public let isVideo: Bool
    public let author: ChatUser

    public var videoAttachment: ChatMessageVideoAttachment?
    public var imageAttachment: ChatMessageImageAttachment?
}
