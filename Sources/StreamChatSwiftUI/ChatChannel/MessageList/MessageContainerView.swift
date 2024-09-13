//
// Copyright © 2024 Stream.io Inc. All rights reserved.
//

import AVKit
import StreamChat
import SwiftUI
import ShinySwiftUI

public struct MessageContainerView<Factory: ViewFactory>: View {

  
    @EnvironmentObject var viewmodel: ChatChannelViewModel
    @Injected(\.fonts) private var fonts
    @Injected(\.colors) private var colors
    @Injected(\.images) private var images
    @Injected(\.chatClient) private var chatClient
    @Injected(\.utils) private var utils

    var factory: Factory
    let channel: ChatChannel
    let message: ChatMessage
    var width: CGFloat?
    var showsAllInfo: Bool
    var isInThread: Bool
    var isLast: Bool
    var isLastGroup: Bool
    @Binding var scrolledId: String?
    @Binding var quotedMessage: ChatMessage?
    @Binding var optionalOffset: CGFloat
    var onLongPress: (MessageDisplayInfo) -> Void

    @State private var frame: CGRect = .zero
    @State private var computeFrame = false
    @State private var offsetX: CGFloat = 0
    @State private var offsetYAvatar: CGFloat = 0
    @GestureState private var offset: CGSize = .zero

    private let replyThreshold: CGFloat = 60
    private let paddingValue: CGFloat = 8

    public init(
        factory: Factory,
        channel: ChatChannel,
        message: ChatMessage,
        width: CGFloat? = nil,
        showsAllInfo: Bool,
        isInThread: Bool,
        isLast: Bool,
        isLastGroup: Bool = false,
        scrolledId: Binding<String?>,
        quotedMessage: Binding<ChatMessage?>,
        onLongPress: @escaping (MessageDisplayInfo) -> Void,
        optionalOffset: Binding<CGFloat>? = nil
    ) {
        self.factory = factory
        self.channel = channel
        self.message = message
        self.width = width
        self.showsAllInfo = showsAllInfo
        self.isInThread = isInThread
        self.isLast = isLast
        self.onLongPress = onLongPress
        self.isLastGroup = isLastGroup
        _scrolledId = scrolledId
        _quotedMessage = quotedMessage
        if let optionalOffset {
          self._optionalOffset = optionalOffset
        } else {
          self._optionalOffset = .constant(.zero)
        }
    }
  
    var offsetDateView: some View {
      GeometryReader { proxy in
        let f = proxy.frame(in: .global)
        let offsetX = UIScreen.main.bounds.maxX - f.minX + (max(optionalOffset, -55)) + 30
        if (offsetX > 2) {
          MessageDateView(message: message)
            .position(x: offsetX, y: f.midY - f.minY)
        }
      }
    }
  
    public var body: some View {
        HStack(alignment: .bottom) {
            if message.type == .system || (message.type == .error && message.isBounced == false) {
                factory.makeSystemMessageView(message: message)
                  .overlay(
                    offsetDateView
                  )
            } else {
                if message.isRightAligned || factory.isSentByCurrentUser(message: message) {
                    MessageSpacer(spacerWidth: spacerWidth)
                } else {
                    if messageListConfig.messageDisplayOptions.showAvatars(for: channel) {
                        factory.makeMessageAvatarView(
                            for: utils.messageCachingUtils.authorInfo(from: message)
                        )
                        .opacity(showsAllInfo || factory.isFirst(message: message) ? 1 : 0)
                        .offset(y: bottomReactionsShown ? offsetYAvatar : 0)
                        .animation(nil)
                    }
                }

                VStack(alignment: message.isRightAligned || factory.isSentByCurrentUser(message: message)  ? .trailing : .leading) {
                    if isMessagePinned {
                        MessagePinDetailsView(
                            message: message,
                            reactionsShown: topReactionsShown
                        )
                    }
                  
                  VStack(alignment: message.isRightAligned || factory.isSentByCurrentUser(message: message) ? .trailing : .leading, spacing: 0) {
                    if !(message.isRightAligned || factory.isSentByCurrentUser(message: message)) && isLastGroup {
                      MessageAuthorView(message: message)
                        .padding(.leading, 10)
                        .offset(y: topReactionsShown ? (message.text.count + 1) < (message.author.name?.count ?? 0) ? -16 : 0 : 0)
                    }
                    MessageView(
                      factory: factory,
                      message: message,
                      contentWidth: contentWidth,
                      isFirst: showsAllInfo,
                      scrolledId: $scrolledId
                    )
                    .overlay(
                      offsetDateView
                    )
                    .overlay(
                      ZStack {
                        topReactionsShown ?
                        factory.makeMessageReactionView(
                          message: message,
                          onTapGesture: {
                            handleGestureForMessage(showsMessageActions: false)
                          },
                          onLongPressGesture: {
                            handleGestureForMessage(showsMessageActions: false)
                          }
                        )
                        : nil
                        
                        (message.localState == .sendingFailed || message.isBounced) ? SendFailureIndicator() : nil
                      }
                    )
                    .background(
                      GeometryReader { proxy in
                        Rectangle().fill(Color.clear)
                          .onChange(of: computeFrame, perform: { _ in
                            DispatchQueue.main.async {
                              frame = proxy.frame(in: .global)
                            }
                          })
                      }
                    )
                    .onTapGesture(count: 2) {
                      if messageListConfig.doubleTapOverlayEnabled {
                        handleGestureForMessage(showsMessageActions: true)
                      }
                    }
                    .onLongPressGesture(minimumDuration: 0.2) {
                      if !message.isDeleted {
                        handleGestureForMessage(showsMessageActions: true)
                      }
                    }
                    .offset(x: min(self.offsetX, maximumHorizontalSwipeDisplacement))
                    .simultaneousGesture(
                      DragGesture(
                        minimumDistance: minimumSwipeDistance,
                        coordinateSpace: .local
                      )
                      .updating($offset) { (value, gestureState, _) in
                        if message.isDeleted || !channel.config.repliesEnabled {
                          return
                        }
                        // Using updating since onEnded is not called if the gesture is canceled.
                        let diff = CGSize(
                          width: value.location.x - value.startLocation.x,
                          height: value.location.y - value.startLocation.y
                        )
                        
                        if diff == .zero {
                          gestureState = .zero
                        } else {
                          gestureState = value.translation
                        }
                      }
                    )
                    .onChange(of: offset, perform: { _ in
                      if !channel.config.quotesEnabled {
                        return
                      }
                      
                      if offset == .zero {
                        // gesture ended or cancelled
                        setOffsetX(value: 0)
                      } else {
                        dragChanged(to: offset.width)
                      }
                    })
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("MessageView")
                  }

                    if message.replyCount > 0 && !isInThread {
                        factory.makeMessageRepliesView(
                            channel: channel,
                            message: message,
                            replyCount: message.replyCount
                        )
                        .accessibilityElement(children: .contain)
                        .accessibility(identifier: "MessageRepliesView")
                    }
                  if message.showReplyInChannel, !isInThread, let quotedMessage = viewmodel.messages.first(where: { message2 in
                    if message2.isRootOfThread {
                      return message2.latestReplies.contains { m in
                        m.id == message.id
                      }
                    } else {
                      return false
                    }
                  }) {
                      MessageThreadReplyView(factory: factory, channel: channel, message: message, repliedMessage: quotedMessage)
                    }
                    
                    if bottomReactionsShown {
                        factory.makeBottomReactionsView(message: message, showsAllInfo: showsAllInfo) {
                            handleGestureForMessage(
                                showsMessageActions: false,
                                showsBottomContainer: false
                            )
                        } onLongPress: {
                            handleGestureForMessage(showsMessageActions: false)
                        }
                        .background(
                            GeometryReader { proxy in
                                let frame = proxy.frame(in: .local)
                                let height = frame.height
                                Color.clear.preference(key: HeightPreferenceKey.self, value: height)
                            }
                        )
                        .onPreferenceChange(HeightPreferenceKey.self) { value in
                            if value != 0 {
                                self.offsetYAvatar = -(value ?? 0)
                            }
                        }
                    }

                    if showsAllInfo && !message.isDeleted {
                        if factory.isSentByCurrentUser(message: message) && channel.config.readEventsEnabled {
                            HStack(spacing: 4) {
                                factory.makeMessageReadIndicatorView(
                                    channel: channel,
                                    message: message
                                )
                            }
                        }
                    }
                }
                .overlay(
                  Group {
                    if #available(iOS 13.0, *) {
                      offsetX > 0 ?
                      TopLeftView {
                        Image(systemName: "arrowshape.turn.up.left.fill")
                          .resizable()
                          .scaledToFit()
                          .frame(width: 12, height: 12)
                          .rotationEffect(.degrees(-44 + offsetX))
                          .padding(8)
                          .background(Color(colors.textLowEmphasis))
                          .clipShape(Circle())
                      }
                      .offset(x: max(-58, -1 * offsetX))
                      .animation(.spring(response: 0.3, dampingFraction: 1.2), value: offsetX)
                      : nil
                    }
                  }
                )

                if !(message.isRightAligned || factory.isSentByCurrentUser(message: message)) {
                    MessageSpacer(spacerWidth: spacerWidth)
                }
            }
        }
        .padding(
            .top,
            topReactionsShown && !isMessagePinned ? messageListConfig.messageDisplayOptions.reactionsTopPadding(message) : 0
        )
        .padding(.horizontal, messageListConfig.messagePaddings.horizontal)
        .padding(.bottom, showsAllInfo || isMessagePinned ? paddingValue : 2)
        .padding(.top, isLast ? paddingValue : 0)
        .background(
          Group {
            if message.isPinned {
              Color.black.opacity(0.3)
            }
          }
        )
        .padding(.bottom, isMessagePinned ? paddingValue / 2 : 0)
        .transition(
            factory.isSentByCurrentUser(message: message) ?
                messageListConfig.messageDisplayOptions.currentUserMessageTransition :
                messageListConfig.messageDisplayOptions.otherUserMessageTransition
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("MessageContainerView")
    }

    private var maximumHorizontalSwipeDisplacement: CGFloat {
        replyThreshold + 30
    }

    private var isMessagePinned: Bool {
        message.pinDetails != nil
    }

    private var contentWidth: CGFloat {
        let padding: CGFloat = messageListConfig.messagePaddings.horizontal
        let minimumWidth: CGFloat = 240
        let available = max(minimumWidth, (width ?? 0) - spacerWidth) - 2 * padding
        let avatarSize: CGFloat = CGSize.messageAvatarSize.width + padding
        let totalWidth = (message.isRightAligned || factory.isSentByCurrentUser(message: message)) ? available : available - avatarSize
        return totalWidth
    }
  
    private var longPressContentWidth: CGFloat {
        let padding: CGFloat = messageListConfig.messagePaddings.horizontal
        let minimumWidth: CGFloat = 240
        let available = max(minimumWidth, (width ?? 0) - (spacerWidth * (4/6))) - 2 * padding
        let avatarSize: CGFloat = CGSize.messageAvatarSize.width + padding
        let totalWidth = (message.isRightAligned || factory.isSentByCurrentUser(message: message)) ? available : available - avatarSize
        return totalWidth
    }


    private var spacerWidth: CGFloat {
        messageListConfig.messageDisplayOptions.spacerWidth(width ?? 0)
    }

    private var topReactionsShown: Bool {
        if messageListConfig.messageDisplayOptions.reactionsPlacement == .bottom {
            return false
        }
        return reactionsShown
    }
    
    private var bottomReactionsShown: Bool {
        if messageListConfig.messageDisplayOptions.reactionsPlacement == .top {
            return false
        }
        return reactionsShown
    }
    
    private var reactionsShown: Bool {
        !message.reactionScores.isEmpty
            && !message.isDeleted
            && channel.config.reactionsEnabled
    }

    private var messageListConfig: MessageListConfig {
        utils.messageListConfig
    }

    private func dragChanged(to value: CGFloat) {
        let horizontalTranslation = value

        if horizontalTranslation < 0 {
            // prevent swiping to right.
            return
        }

        if horizontalTranslation >= minimumSwipeDistance {
            offsetX = horizontalTranslation
        } else {
            offsetX = 0
        }

        if offsetX > replyThreshold && quotedMessage != message {
            triggerHapticFeedback(style: .medium)
            withAnimation {
                quotedMessage = message
            }
        }
    }

    private var minimumSwipeDistance: CGFloat {
        utils.messageListConfig.messageDisplayOptions.minimumSwipeGestureDistance
    }

    private func setOffsetX(value: CGFloat) {
        withAnimation(.interpolatingSpring(stiffness: 170, damping: 20)) {
            self.offsetX = value
        }
    }

    private func handleGestureForMessage(
        showsMessageActions: Bool,
        showsBottomContainer: Bool = true
    ) {
        computeFrame = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            computeFrame = false
            triggerHapticFeedback(style: .medium)
            onLongPress(
                MessageDisplayInfo(
                    message: message,
                    frame: frame,
                    contentWidth: longPressContentWidth,
                    isFirst: showsAllInfo,
                    showsMessageActions: showsMessageActions,
                    showsBottomContainer: showsBottomContainer
                )
            )
        }
    }
}

struct SendFailureIndicator: View {

    @Injected(\.colors) private var colors
    @Injected(\.images) private var images

    var body: some View {
        BottomRightView {
            Image(uiImage: images.messageListErrorIndicator)
                .customizable()
                .frame(width: 16, height: 16)
                .foregroundColor(Color(colors.alert))
                .offset(y: 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("SendFailureIndicator")
    }
}

public struct MessageDisplayInfo {
    public let message: ChatMessage
    public let frame: CGRect
    public let contentWidth: CGFloat
    public let isFirst: Bool
    public var showsMessageActions: Bool = true
    public var showsBottomContainer: Bool = true
    public var keyboardWasShown: Bool = false

    public init(
        message: ChatMessage,
        frame: CGRect,
        contentWidth: CGFloat,
        isFirst: Bool,
        showsMessageActions: Bool = true,
        showsBottomContainer: Bool = true,
        keyboardWasShown: Bool = false
    ) {
        self.message = message
        self.frame = frame
        self.contentWidth = contentWidth
        self.isFirst = isFirst
        self.showsMessageActions = showsMessageActions
        self.keyboardWasShown = keyboardWasShown
        self.showsBottomContainer = showsBottomContainer
    }
}


extension View {
    func delaysTouches(for duration: TimeInterval = 0.25, onTap action: @escaping () -> Void = {}) -> some View {
        modifier(DelaysTouches(duration: duration, action: action))
    }
}

fileprivate struct DelaysTouches: ViewModifier {
    @State private var disabled = false
    @State private var touchDownDate: Date? = nil
    
    var duration: TimeInterval
    var action: () -> Void
    
    func body(content: Content) -> some View {
        Button(action: action) {
            content
        }
        .buttonStyle(DelaysTouchesButtonStyle(disabled: $disabled, duration: duration, touchDownDate: $touchDownDate))
        .disabled(disabled)
    }
}

fileprivate struct DelaysTouchesButtonStyle: ButtonStyle {
    @Binding var disabled: Bool
    var duration: TimeInterval
    @Binding var touchDownDate: Date?
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed, perform: handleIsPressed)
    }
    
    private func handleIsPressed(isPressed: Bool) {
        if isPressed {
            let date = Date()
            touchDownDate = date
            
            DispatchQueue.main.asyncAfter(deadline: .now() + max(duration, 0)) {
                if date == touchDownDate {
                    disabled = true
                    
                    DispatchQueue.main.async {
                        disabled = false
                    }
                }
            }
        } else {
            touchDownDate = nil
            disabled = false
        }
    }
}
