//
//  ReplyContextModifier.swift
//  Poppin: puts the original above a list row whose message answers it.
//

import StreamChat
import SwiftUI

/// Wraps one row of the message list. A row whose message quotes another one gets Apple
/// Messages' reply layout (`ReplyContextStack`): the original above it as its own block, the
/// line between the two, and a tap on the original opens its thread in the reply view. Every
/// other row, and every row while `MessageListConfig.replyThreadEnabled` is off, passes through.
struct ReplyContextModifier<Factory: ViewFactory>: ViewModifier {

    @EnvironmentObject private var viewModel: ChatChannelViewModel
    @Injected(\.utils) private var utils
    @Injected(\.chatClient) private var chatClient

    var factory: Factory
    var channel: ChatChannel
    var message: ChatMessage
    /// The row opens with its sender's name (the list draws it over the row's top).
    var rowOpensWithName: Bool

    func body(content: Content) -> some View {
        if let original {
            ReplyContextStack(
                style: utils.messageListConfig.replyStyle,
                quoteIsTrailing: isOwn(original),
                replyIsTrailing: isOwn(message),
                rowPadding: utils.messageListConfig.messagePaddings.horizontal,
                faceColumnWidth: showsFaces ? CGSize.messageAvatarSize.width : nil,
                rowOpensWithName: rowOpensWithName,
                quote: {
                    factory.makeReplyContextView(for: message, quotedMessage: original, channel: channel)
                        .onTapGesture {
                            withAnimation {
                                viewModel.quotedMessage = original
                            }
                        }
                },
                face: {
                    factory.makeQuotedMessageAvatarView(
                        for: utils.messageCachingUtils.authorInfo(from: original),
                        size: CGSize(width: faceSize, height: faceSize)
                    )
                },
                row: { content }
            )
        } else {
            content
        }
    }

    /// The message this row answers: the loaded one when the list holds it (its pictures and
    /// attachments are there), the short preview the reply carries otherwise.
    private var original: ChatMessage? {
        guard utils.messageListConfig.replyThreadEnabled,
              ReplyThreads.isReply(message),
              let quoted = message.quotedMessage else { return nil }
        return viewModel.replyThreads.loaded[quoted.id] ?? quoted
    }

    /// A preview does not say whose it is, so the sender's id decides as well.
    private func isOwn(_ message: ChatMessage) -> Bool {
        message.isRightAligned
            || factory.isSentByCurrentUser(message: message)
            || message.author.id == chatClient.currentUserId
    }

    private var showsFaces: Bool {
        utils.messageListConfig.messageDisplayOptions.showAvatars(for: channel)
    }

    private var faceSize: CGFloat {
        utils.messageListConfig.replyStyle.faceSize
    }
}

/// What a list row shows of the reply threads. `MessageListView` works it out and hands it
/// down: the row view is also drawn outside a conversation (a message's Info page), where no
/// channel view model exists to ask.
struct ReplyRowInfo: Equatable {
    /// Loaded replies that lead back to the row's message ("1 Reply").
    var replyCount = 0
    /// The next (newer) row opens with a date line.
    var dateLineFollows = false
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
