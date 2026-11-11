//
//  ReplyContextModifier.swift
//  Poppin: puts the original above the first reply of a run, and the thread line over a row.
//

import StreamChat
import SwiftUI

/// Wraps one row of the message list. The first reply of a run that stands away from its
/// original gets the original above it (`ReplyContextStack`), with "N Replies" under it when
/// the thread has more than one reply; a tap on either opens the thread in the reply view.
/// Every other row, and every row while `MessageListConfig.replyThreadEnabled` is off, passes
/// through.
struct ReplyContextModifier<Factory: ViewFactory>: ViewModifier {

    @EnvironmentObject private var viewModel: ChatChannelViewModel
    @Injected(\.utils) private var utils

    var factory: Factory
    var channel: ChatChannel
    var message: ChatMessage
    /// The row opens with its sender's name (the list draws it over the row's top).
    var rowOpensWithName: Bool
    /// What the list worked out for the row (`MessageListView.replyRowInfo`).
    var info: ReplyRowInfo

    func body(content: Content) -> some View {
        if let line = info.line, let side = line.quote, let original {
            ReplyContextStack(
                style: utils.messageListConfig.replyStyle,
                quoteIsTrailing: side == .trailing,
                replyIsTrailing: line.bubble == .trailing,
                rowPadding: utils.messageListConfig.messagePaddings.horizontal,
                faceColumnWidth: showsFaces ? CGSize.messageAvatarSize.width : nil,
                rowOpensWithName: rowOpensWithName,
                showsCount: info.quoteReplyCount > 1,
                followsMessage: info.followsMessage,
                quote: {
                    factory.makeReplyContextView(for: message, quotedMessage: original, channel: channel)
                        .onTapGesture { open(original) }
                },
                face: {
                    factory.makeQuotedMessageAvatarView(
                        for: utils.messageCachingUtils.authorInfo(from: original),
                        size: CGSize(width: faceSize, height: faceSize)
                    )
                },
                count: {
                    factory.makeReplyCountView(for: original, count: info.quoteReplyCount)
                        .onTapGesture { open(original) }
                },
                row: { content }
            )
        } else {
            content
        }
    }

    /// The thread's first message: the loaded one when the list holds it (its pictures and
    /// attachments are there), the short preview a reply carries of it otherwise.
    private var original: ChatMessage? {
        guard let id = info.quoteId else { return nil }
        return viewModel.replyThreads.message(id)
    }

    private func open(_ original: ChatMessage) {
        withAnimation {
            viewModel.quotedMessage = original
        }
    }

    private var showsFaces: Bool {
        utils.messageListConfig.messageDisplayOptions.showAvatars(for: channel)
    }

    private var faceSize: CGFloat {
        utils.messageListConfig.replyStyle.faceSize
    }
}

/// Draws the thread line over one whole row of the list, its date line included
/// (`ReplyThreadLine`). Off with `MessageListConfig.replyThreadEnabled`.
struct ReplyRowLineModifier: ViewModifier {

    @Injected(\.utils) private var utils

    var channel: ChatChannel
    var info: ReplyLineInfo?
    /// How far the list has slid the row's bubbles aside (the drag that shows the times).
    var slide: CGFloat = 0

    func body(content: Content) -> some View {
        if utils.messageListConfig.replyThreadEnabled {
            content.modifier(ReplyThreadLine(
                info: info,
                style: utils.messageListConfig.replyStyle,
                rowPadding: utils.messageListConfig.messagePaddings.horizontal,
                faceColumnWidth: utils.messageListConfig.messageDisplayOptions.showAvatars(for: channel)
                    ? CGSize.messageAvatarSize.width
                    : nil,
                slide: slide
            ))
        } else {
            content
        }
    }
}

/// What a list row shows of the reply threads. `MessageListView` works it out and hands it
/// down: the row view is also drawn outside a conversation (a message's Info page), where no
/// channel view model exists to ask.
struct ReplyRowInfo: Equatable {
    /// Loaded replies that lead back to the row's message ("N Replies" under it).
    var replyCount = 0
    /// The next (newer) row opens with a date line.
    var dateLineFollows = false
    /// A message follows this row: not a date line, and not the first block of a thread
    /// (both keep their own distance).
    var messageFollows = false
    /// The thread line through the row; nil for a row outside any run of replies.
    var line: ReplyLineInfo?
    /// The original drawn above the row (the first reply of a run away from its original),
    /// and how many loaded replies its thread has.
    var quoteId: MessageId?
    var quoteReplyCount = 0
    /// The row opens a thread's block (it is an original with replies, or carries the outlined
    /// original above it) and the row before it is a message, not a date line: Messages keeps
    /// a thread apart from the messages around it.
    var followsMessage = false
    /// The row under this one opens with its sender's name (a group chat).
    var nextOpensWithName = false

    /// The row is an original with its replies right under it: its "N Replies" is seated
    /// beside the line, and shows only when the thread has more than the one under it.
    var opensRun: Bool {
        line.map { !$0.isReply && $0.leavesBelow } ?? false
    }

    /// The row is the last of a run of replies.
    var endsRun: Bool {
        line.map { $0.isReply && !$0.leavesBelow } ?? false
    }
}

private struct ReplyRowInfoKey: EnvironmentKey {
    static let defaultValue = ReplyRowInfo()
}

private struct ReplyViewCoversListKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var replyRowInfo: ReplyRowInfo {
        get { self[ReplyRowInfoKey.self] }
        set { self[ReplyRowInfoKey.self] = newValue }
    }

    /// The reply view covers the list this row is in.
    var replyViewCoversList: Bool {
        get { self[ReplyViewCoversListKey.self] }
        set { self[ReplyViewCoversListKey.self] = newValue }
    }
}
