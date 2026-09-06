//
// Copyright © 2024 Stream.io Inc. All rights reserved.
//

import Foundation
import StreamChat
import UIKit

open class ChannelHeaderLoader: ObservableObject {
    @Injected(\.images) private var images
    @Injected(\.utils) private var utils
    @Injected(\.chatClient) private var chatClient

    /// The maximum number of images that combine to form a single avatar
    private let maxNumberOfImagesInCombinedAvatar = 4

    /// Prevents image requests to be executed if they failed previously. Poppin: keyed by
    /// the image URL for channel thumbnails (a corrected URL for the same channel is tried
    /// again — a repaired flyer copy used to stay a placeholder until relaunch); merged
    /// avatars stay keyed by channel id.
    private var failedImageLoads = Set<String>()

    /// Poppin: the URL each cached channel thumbnail was loaded from, so a channel whose
    /// `imageURL` changes underneath reloads instead of serving the stale bitmap forever.
    private var loadedImageURLs = [String: String]()

    /// Batches loaded images for update, to improve performance.
    private var scheduledUpdate = false

    /// Context provided utils.
    internal lazy var imageLoader = utils.imageLoader
    internal lazy var imageCDN = utils.imageCDN
    internal lazy var channelAvatarsMerger = utils.channelAvatarsMerger
    internal lazy var channelNamer = utils.channelNamer

    /// Placeholder images.
    internal lazy var placeholder1 = images.userAvatarPlaceholder1
    internal lazy var placeholder2 = images.userAvatarPlaceholder2
    internal lazy var placeholder3 = images.userAvatarPlaceholder3
    internal lazy var placeholder4 = images.userAvatarPlaceholder4

    var loadedImages = [String: UIImage]() {
        willSet {
            if !scheduledUpdate {
                scheduledUpdate = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.objectWillChange.send()
                    self?.scheduledUpdate = false
                }
            }
        }
    }

    public init() {
        // Public init.
    }

    /// Loads an image for the provided channel.
    /// If the image is not downloaded, placeholder is returned.
    /// - Parameter channel: the provided channel.
    /// - Returns: the available image.
    public func image(for channel: ChatChannel) -> UIImage {
        let key = channel.cid.rawValue

        if let url = channel.imageURL {
            // The cached bitmap is only good for the URL it was loaded from; while a new
            // URL loads, keep showing the old image rather than flashing the placeholder.
            if let image = loadedImages[key], loadedImageURLs[key] == url.absoluteString {
                return image
            }
            loadChannelThumbnail(for: channel, from: url)
            return loadedImages[key] ?? placeholder4
        }

        if let image = loadedImages[key] {
            return image
        }

        if channel.isDirectMessageChannel && channel.lastActiveMembers.count == 2 {
            let lastActiveMembers = self.lastActiveMembers(for: channel)
            if let otherMember = lastActiveMembers.first, let url = otherMember.imageURL {
                loadChannelThumbnail(for: channel, from: url)
                return placeholder3
            } else {
                return placeholder4
            }
        } else {
            let activeMembers = lastActiveMembers(for: channel)

            if activeMembers.isEmpty {
                return placeholder4
            }

            let urls = activeMembers
                .compactMap(\.imageURL)
                .prefix(maxNumberOfImagesInCombinedAvatar)

            if urls.isEmpty {
                return placeholder3
            } else {
                loadMergedAvatar(from: channel, urls: Array(urls))
                return placeholder4
            }
        }
    }

    // MARK: - private

    private func loadMergedAvatar(from channel: ChatChannel, urls: [URL]) {
        if failedImageLoads.contains(channel.cid.rawValue) {
            return
        }

        imageLoader.loadImages(
            from: urls,
            placeholders: [],
            loadThumbnails: true,
            thumbnailSize: .avatarThumbnailSize,
            imageCDN: imageCDN
        ) { [weak self] images in
            guard let self = self else { return }
            DispatchQueue.global(qos: .userInteractive).async {
                let image = self.channelAvatarsMerger.createMergedAvatar(from: images)
                DispatchQueue.main.async {
                    if let image = image {
                        self.loadedImages[channel.cid.rawValue] = image
                    } else {
                        self.failedImageLoads.insert(channel.cid.rawValue)
                    }
                }
            }
        }
    }

    private func loadChannelThumbnail(
        for channel: ChatChannel,
        from url: URL
    ) {
        let urlKey = url.absoluteString
        if failedImageLoads.contains(urlKey) {
            return
        }

        imageLoader.loadImage(
            url: url,
            imageCDN: imageCDN,
            resize: true,
            preferredSize: .avatarThumbnailSize
        ) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case let .success(image):
                DispatchQueue.main.async {
                    self.loadedImageURLs[channel.cid.rawValue] = urlKey
                    self.loadedImages[channel.cid.rawValue] = image
                }
            case let .failure(error):
                self.failedImageLoads.insert(urlKey)
                log.error("error loading image: \(error.localizedDescription)")
            }
        }
    }

    private func lastActiveMembers(for channel: ChatChannel) -> [ChatChannelMember] {
        channel.lastActiveMembers
            .sorted { $0.memberCreatedAt < $1.memberCreatedAt }
            .filter { $0.id != chatClient.currentUserId }
    }
}
