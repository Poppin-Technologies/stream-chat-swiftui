//
// Copyright © 2024 Stream.io Inc. All rights reserved.
//

import StreamChat
import SwiftUI

enum MessageRepliesConstants {
    static let selectedMessageThread = "selectedMessageThread"
    static let selectedMessage = "selectedMessage"
}

/// View shown below a message, when there are replies to it.
public struct MessageRepliesView<Factory: ViewFactory>: View {

    @Injected(\.fonts) private var fonts
    @Injected(\.colors) private var colors
    @Injected(\.utils) private var utils

    var factory: Factory
    var channel: ChatChannel
    var message: ChatMessage
    var replyCount: Int

    public init(factory: Factory, channel: ChatChannel, message: ChatMessage, replyCount: Int) {
        self.factory = factory
        self.channel = channel
        self.message = message
        self.replyCount = replyCount
    }

    public var body: some View {
        Button {
            // NOTE: Needed because of a bug in iOS 16.
            resignFirstResponder()
            // NOTE: this is used to avoid breaking changes.
            // Will be updated in a major release.
            NotificationCenter.default.post(
                name: NSNotification.Name(MessageRepliesConstants.selectedMessageThread),
                object: nil,
                userInfo: [MessageRepliesConstants.selectedMessage: message]
            )
        } label: {
            HStack {
                if !utils.isSentByCurrentUser(message) {
                    MessageAvatarView(
                        avatarURL: message.threadParticipants.first?.imageURL,
                        size: .init(width: 16, height: 16)
                    )
                }
                Text("\(replyCount) \(repliesText)")
                    .font(fonts.footnoteBold)
                if utils.isSentByCurrentUser(message) {
                    MessageAvatarView(
                        avatarURL: message.threadParticipants.first?.imageURL,
                        size: .init(width: 16, height: 16)
                    )
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 5)
            .background(
              Color.black.opacity(0.3)
            )
            .clipShape(Capsule())
            .padding(.horizontal, 5)
            .foregroundColor(colors.tintColor)
            .offset(y: -3)
        }
    }

    var repliesText: String {
        if message.replyCount == 1 {
            return L10n.Message.Threads.reply
        } else {
            return L10n.Message.Threads.replies
        }
    }
}

/// View shown below a message, when there are replies to it.
public struct MessageThreadReplyView<Factory: ViewFactory>: View {
  
  @Injected(\.fonts) private var fonts
  @Injected(\.colors) private var colors
  
  var factory: Factory
  var channel: ChatChannel
  var message: ChatMessage
  var repliedMessage: ChatMessage
  
  public init(factory: Factory, channel: ChatChannel, message: ChatMessage, repliedMessage: ChatMessage) {
    self.factory = factory
    self.channel = channel
    self.message = message
    self.repliedMessage = repliedMessage
  }
  
  public var body: some View {
    Button {
      // NOTE: Needed because of a bug in iOS 16.
      resignFirstResponder()
      // NOTE: this is used to avoid breaking changes.
      // Will be updated in a major release.
      NotificationCenter.default.post(
        name: NSNotification.Name(MessageRepliesConstants.selectedMessageThread),
        object: nil,
        userInfo: [MessageRepliesConstants.selectedMessage: repliedMessage]
      )
    } label: {
      HStack {
        if !(message.isRightAligned || factory.isSentByCurrentUser(message: message)) {
            MessageAvatarView(
                avatarURL: repliedMessage.author.imageURL,
                size: .init(width: 16, height: 16)
            )
        }
        Text("Replied to thread \(repliedMessage.adjustedText)").font(fonts.footnoteBold)
        .lineLimit(1)
        if (message.isRightAligned || factory.isSentByCurrentUser(message: message)) {
            MessageAvatarView(
              avatarURL: repliedMessage.author.imageURL,
                size: .init(width: 16, height: 16)
            )
        }
      }
      .padding(.vertical, 3)
      .padding(.horizontal, 5)
      .background(
        Color.black.opacity(0.3)
      )
      .clipShape(Capsule())
      .padding(.horizontal, 5)
      .foregroundColor(colors.tintColor)
      .offset(y: -3)
    }
  }
}
