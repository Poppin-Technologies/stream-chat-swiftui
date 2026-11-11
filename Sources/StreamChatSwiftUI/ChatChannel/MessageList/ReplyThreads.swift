//
//  ReplyThreads.swift
//  Poppin: which loaded messages answer which (Apple Messages' reply threads).
//

import StreamChat
import SwiftUI

/// The reply threads among the messages a conversation has loaded. A reply quotes one message;
/// a thread is the message that chain of quotes leads back to (its root) and every loaded
/// message whose chain reaches it, so a reply to a reply stays in the thread of the first one.
/// Built once per change of the list (`ChatChannelViewModel.messages`); the row, the
/// "1 Reply" line and the reply view all read this one index.
public struct ReplyThreads {

    /// The loaded messages by id.
    public private(set) var loaded: [MessageId: ChatMessage] = [:]
    private var rootOf: [MessageId: MessageId] = [:]
    private var repliesOf: [MessageId: [ChatMessage]] = [:]

    public init() {}

    /// - Parameter messages: the conversation's loaded messages, newest first (as the list
    ///   holds them).
    public init(messages: [ChatMessage]) {
        var quotedIdOf = [MessageId: MessageId]()
        for message in messages {
            loaded[message.id] = message
            // A deleted reply still joins its neighbours: the chain runs through it, it is
            // only left out of the thread's replies below.
            if message.type != .system, let quotedId = message.quotedMessage?.id {
                quotedIdOf[message.id] = quotedId
            }
        }
        for message in messages.reversed() where Self.isReply(message) {
            // Up the chain of quotes; a chain longer than any real one ends the walk (a loop
            // cannot be built through the app, the cap only keeps a bad payload from hanging).
            var root = message.id
            var steps = 0
            while let next = quotedIdOf[root], steps < 64 {
                root = next
                steps += 1
            }
            rootOf[message.id] = root
            repliesOf[root, default: []].append(message)
        }
    }

    /// A message that draws as a reply: it quotes another one and is still there.
    public static func isReply(_ message: ChatMessage) -> Bool {
        message.quotedMessage != nil && !message.isDeleted && message.type != .system
    }

    /// The root of the thread a message belongs to; its own id when it answers nothing.
    public func rootId(of messageId: MessageId) -> MessageId {
        rootOf[messageId] ?? messageId
    }

    /// The loaded replies of the thread a message roots, oldest first.
    public func replies(toRoot rootId: MessageId) -> [ChatMessage] {
        repliesOf[rootId] ?? []
    }

    /// How many loaded replies lead back to this message; 0 for a message that is itself a reply.
    public func replyCount(of messageId: MessageId) -> Int {
        repliesOf[messageId]?.count ?? 0
    }
}
