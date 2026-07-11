//
// Copyright © 2024 Stream.io Inc. All rights reserved.
//

import Combine
import StreamChat
import SwiftUI

open class ReactionsOverlayViewModel: ObservableObject, ChatMessageControllerDelegate {
    @Injected(\.chatClient) private var chatClient
    @Injected(\.utils) private var utils

    @Published public var message: ChatMessage {
        didSet {
            reactions = Self.reactions(from: message)
        }
    }
    
    @Published public var errorShown = false
    @Published public var reactions: [MessageReactionType]

    private var messageController: ChatMessageController?

    public init(message: ChatMessage) {
        self.message = message
        reactions = Self.reactions(from: message)
        makeMessageController(for: message)
    }

    public func reactionTapped(_ reaction: MessageReactionType) {
        // The overlay dismisses the moment the user taps, so `errorShown`'s alert can never
        // render for a reaction - failures used to be 100% silent. The engine now applies the
        // reaction optimistically and REVERTS it on failure (the visible un-apply is the
        // primary feedback); this completion adds a log line + a NotificationCenter hook the
        // app can observe for a toast.
        let completion: (Error?) -> Void = { error in
            guard let error else { return }
            log.error("Reaction tap failed: \(error)")
            NotificationCenter.default.post(name: .chatActionFailed, object: nil, userInfo: ["error": error])
        }
        if userReactionIDs.contains(reaction) {
            // reaction should be removed
            messageController?.deleteReaction(reaction, completion: completion)
        } else {
            // reaction should be added
            messageController?.addReaction(
                reaction,
                enforceUnique: utils.messageListConfig.uniqueReactionsEnabled,
                completion: completion
            )
        }
    }

    // MARK: - ChatMessageControllerDelegate

    public func messageController(
        _ controller: ChatMessageController,
        didChangeMessage change: EntityChange<ChatMessage>
    ) {
        if let message = controller.message {
            withAnimation {
                self.message = message
            }
        }
    }

    // MARK: - private
    
    private static func reactions(from message: ChatMessage) -> [MessageReactionType] {
        message.reactionScores.keys.filter { reactionType in
            (message.reactionScores[reactionType] ?? 0) > 0
        }
        .sorted(by: InjectedValues[\.utils].sortReactions)
    }

    private func makeMessageController(for message: ChatMessage) {
        let controllerFactory = InjectedValues[\.utils].channelControllerFactory
        if let channelId = message.cid {
            messageController = controllerFactory.makeMessageController(
                for: message.id,
                channelId: channelId
            )
            messageController?.delegate = self
            if let message = messageController?.message {
                self.message = message
            }
        }
    }

    private var userReactionIDs: Set<MessageReactionType> {
        Set(message.currentUserReactions.map(\.type))
    }
}

public extension Notification.Name {
    /// Posted when a fire-and-forget chat menu action (currently: reaction add/remove) fails
    /// after its UI already dismissed. `userInfo["error"]` carries the `Error`. The app layer
    /// may observe this to show a toast; the engine's optimistic revert already provides the
    /// in-place visual feedback.
    static let chatActionFailed = Notification.Name("io.getstream.StreamChatSwiftUI.chatActionFailed")
}
