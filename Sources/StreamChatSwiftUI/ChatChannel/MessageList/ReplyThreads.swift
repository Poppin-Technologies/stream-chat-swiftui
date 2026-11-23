//
//  ReplyThreads.swift
//  Poppin: which loaded messages answer which (Apple Messages' reply threads).
//

import StreamChat
import SwiftUI

/// The reply threads among the messages a conversation has loaded. A reply quotes one message;
/// a thread is the message that chain of quotes leads back to (its root) and every loaded
/// message whose chain reaches it, so a reply to a reply stays in the thread of the first one.
/// Replies that stand right under their root, or right under another reply of their thread,
/// form a run: the list joins a run with one line and shows the root once, above its first
/// reply. A run is about one thing: replies to different tasks of a checklist stand in runs
/// of their own, each under an outline that names its task.
/// Built once per change of the list (`ChatChannelViewModel.messages`); the rows, the
/// "N Replies" line and the reply view all read this one index.
public struct ReplyThreads {

    /// The loaded messages by id.
    public private(set) var loaded: [MessageId: ChatMessage] = [:]
    /// The short preview a reply carries of a message the list has not loaded.
    private var previews: [MessageId: ChatMessage] = [:]
    private var rootOf: [MessageId: MessageId] = [:]
    private var repliesOf: [MessageId: [ChatMessage]] = [:]
    /// The row right above (older) and right under (newer) a row, when the two are joined.
    private var aboveOf: [MessageId: MessageId] = [:]
    private var belowOf: [MessageId: MessageId] = [:]
    /// The row right under (newer than) a row, joined or not.
    private var newerOf: [MessageId: MessageId] = [:]

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
        var taskOf = [MessageId: String]()
        var older: ChatMessage?
        for message in messages.reversed() {
            if let older {
                newerOf[older.id] = message.id
            }
            defer { older = message }
            if message.type != .system,
               let quoted = message.quotedMessage,
               loaded[quoted.id] == nil,
               previews[quoted.id] == nil {
                previews[quoted.id] = quoted
            }
            guard Self.isReply(message) else { continue }
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
            // The task of a checklist this reply is about ("Reply to Item", 2026-11-22): the
            // one its own quote names, and for a reply to a reply the task of the one it answers.
            let task = message.quotedMessage.flatMap { $0.quotedChecklistTask?.id ?? taskOf[$0.id] }
            if let task {
                taskOf[message.id] = task
            }
            // Joined to the row above: the root itself, or an earlier reply of the thread. A
            // reply about one task of a checklist joins only a reply about that same task, and
            // never the list itself: the outline over a run is where its task is named, so a
            // run ends where the task changes.
            if let older {
                let joins = older.id == root
                    ? task == nil
                    : Self.isReply(older) && rootOf[older.id] == root && taskOf[older.id] == task
                if joins {
                    aboveOf[message.id] = older.id
                    belowOf[older.id] = message.id
                }
            }
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

    /// A message by id: the loaded one, or the short preview a reply carries of it.
    public func message(_ messageId: MessageId) -> ChatMessage? {
        loaded[messageId] ?? previews[messageId]
    }

    /// The loaded replies of the thread a message roots, oldest first.
    public func replies(toRoot rootId: MessageId) -> [ChatMessage] {
        repliesOf[rootId] ?? []
    }

    /// How many loaded replies lead back to this message; 0 for a message that is itself a reply.
    public func replyCount(of messageId: MessageId) -> Int {
        repliesOf[messageId]?.count ?? 0
    }

    /// The row right above that this reply is joined to: its root, or an earlier reply of its
    /// thread. Nil for a reply that opens a run away from its root.
    public func joinedAbove(_ messageId: MessageId) -> MessageId? {
        aboveOf[messageId]
    }

    /// The reply right under this row that is joined to it.
    public func joinedBelow(_ messageId: MessageId) -> MessageId? {
        belowOf[messageId]
    }

    /// The row right under (newer than) this one.
    public func newer(than messageId: MessageId) -> MessageId? {
        newerOf[messageId]
    }
}
