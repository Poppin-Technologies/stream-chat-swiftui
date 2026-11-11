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
    @Environment(\.isNewestMessageRow) private var isNewestMessageRow
    @Environment(\.replyRowInfo) private var replyRowInfo
    @Environment(\.replyViewCoversList) private var replyViewCoversList

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
    var bypassGrouping: Bool = false
    @State private var frame: CGRect = .zero
    @State private var computeFrame = false
    @State private var offsetX: CGFloat = 0
    @State private var offsetYAvatar: CGFloat = 0
    @GestureState private var offset: CGSize = .zero

    private let replyThreshold: CGFloat = 60
    private let paddingValue: CGFloat = 8
    // Poppin: the room under a bubble is Messages' (read off Jackie's screenshots, IMG_2035
    // and IMG_2037): 9pt under the last bubble of a run, 1pt between one sender's back to
    // back bubbles. The app's date line and reply numbers are tuned on top of these two.
    private let runBottomGap: CGFloat = 9
    private let bubbleBottomGap: CGFloat = 1

    public init(
        factory: Factory,
        channel: ChatChannel,
        message: ChatMessage,
        width: CGFloat? = nil,
        showsAllInfo: Bool,
        isInThread: Bool,
        isLast: Bool,
        isLastGroup: Bool = false,
        bypassGrouping: Bool = false,
        scrolledId: Binding<String?>,
        quotedMessage: Binding<ChatMessage?>,
        onLongPress: @escaping (MessageDisplayInfo) -> Void,
        optionalOffset: Binding<CGFloat>? = nil
    ) {
        self.factory = factory
        self.channel = channel
        self.message = message
        self.bypassGrouping = bypassGrouping
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
                    if messageListConfig.messageDisplayOptions.showAvatars(for: channel) || bypassGrouping {
                        factory.makeMessageAvatarView(
                            for: utils.messageCachingUtils.authorInfo(from: message)
                        )
                        .opacity(showsAllInfo || factory.isFirst(message: message) ? 1 : 0)
                        .offset(y: bottomReactionsShown ? offsetYAvatar : 0)
                        .animation(nil)
                        // Poppin: a face that is laid out but not shown does not stop the thread line.
                        .replyAnchor(showsAllInfo || factory.isFirst(message: message) ? .replyFace : nil)
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
                    messageViewWithOverlays
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
                  // Poppin: with its replies right under it, "N Replies" sits beside the line and
                  // takes no room (the first reply is placed by `rowBottomPadding`). On the
                  // bubble's column, not on the bubble: a tap or a swipe on the label is not
                  // the bubble's.
                  .modifier(seatedReplyCount)

                    replyCountLine

                    if message.replyCount > 0 && !isInThread {
                        factory.makeMessageRepliesView(
                            channel: channel,
                            message: message,
                            replyCount: message.replyCount
                        )
                        .accessibilityElement(children: .contain)
                        .accessibility(identifier: "MessageRepliesView")
                    }
                  if message.showReplyInChannel, !isInThread, let quotedMessage = threadRootContainingReply {
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

                    // Poppin: only under the conversation's newest message, the way Messages shows
                    // "Delivered" (a tick row under every run pushed the next date line ~30pt down).
                    if showsAllInfo && !message.isDeleted && isNewestMessageRow {
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
        .padding(.bottom, rowBottomPadding)
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

    // Extracted from `body`'s `.overlay(...)` chain: the compiler couldn't type-check the
    // two stacked ternaries (each returning `nil` on one branch) inline within a reasonable
    // time. Splitting into its own `@ViewBuilder` property is functionally identical, just
    // faster for the type-checker to resolve.
    @ViewBuilder
    private var reactionAndFailureOverlay: some View {
        ZStack {
            if topReactionsShown {
                factory.makeMessageReactionView(
                    message: message,
                    onTapGesture: {
                        handleGestureForMessage(showsMessageActions: false)
                    },
                    onLongPressGesture: {
                        handleGestureForMessage(showsMessageActions: false)
                    }
                )
            }

            if message.localState == .sendingFailed || message.isBounced {
                SendFailureIndicator()
            }
        }
    }

    // Same extraction as `reactionAndFailureOverlay` above: the type-checker timed out on this
    // `.background(GeometryReader { ... })` once it followed the preceding overlay chain inline.
    private var frameTrackingBackground: some View {
        GeometryReader { proxy in
            Rectangle().fill(Color.clear)
                .onChange(of: computeFrame, perform: { _ in
                    DispatchQueue.main.async {
                        frame = proxy.frame(in: .global)
                    }
                })
        }
    }

    // Further extraction: even with the two properties above, the type-checker still timed out
    // trying to resolve the *rest* of the chain (gesture modifiers, onChange) as one expression
    // continuing straight off `MessageView(...)`. Isolating "MessageView + its overlays/background"
    // into its own property lets the remaining gesture-modifier chain in `body` type-check as a
    // separate, much shorter expression.
    private var messageViewWithOverlays: some View {
        MessageView(
            factory: factory,
            message: message,
            contentWidth: contentWidth,
            isFirst: showsAllInfo,
            scrolledId: $scrolledId
        )
        .overlay(offsetDateView)
        .overlay(reactionAndFailureOverlay)
        .background(frameTrackingBackground)
        .background(replySwipeRegion)
        // Poppin: the thread line starts, stops or turns at this bubble (ReplyThreadLine).
        .replyAnchor(.bubble)
    }

    // Poppin: the bubble owns a right swipe that starts on it (swipe to reply, below); see
    // `MessageListConfig.replySwipeRegion`.
    @ViewBuilder
    private var replySwipeRegion: some View {
        // Not under the reply view: a bubble nobody can see must not decide what a swipe does.
        if let region = messageListConfig.replySwipeRegion,
           !replyViewCoversList,
           channel.config.quotesEnabled,
           !message.isDeleted {
            region()
        }
    }

    // Poppin: "1 Reply" under a message that loaded messages answer (Messages); a tap opens
    // the thread in the reply view. The count comes from the list (`ReplyRowInfo`). Its own
    // properties for the type checker, like the ones above.
    private var replyCountLabel: some View {
        factory.makeReplyCountView(for: message, count: replyRowInfo.replyCount)
            .onTapGesture {
                withAnimation {
                    quotedMessage = message
                }
            }
    }

    private var seatedReplyCount: some ViewModifier {
        ReplyCountSeat(
            isShown: showsReplyCount && seatsReplyCount,
            isTrailing: replyRowInfo.line?.bubble == .trailing,
            spacing: messageListConfig.replyStyle.countSpacing,
            shift: replyCountShift,
            label: replyCountLabel
        )
    }

    // In the row's column, under the bubble: every case but the seated one.
    @ViewBuilder
    private var replyCountLine: some View {
        if showsReplyCount, !seatsReplyCount {
            replyCountLabel
                .padding(.leading, replyCountShift)
        }
    }

    // With its replies right under it an original says how many only when there are more
    // than the one the eye already sees.
    private var showsReplyCount: Bool {
        replyRowInfo.opensRun ? replyRowInfo.replyCount > 1 : replyRowInfo.replyCount > 0
    }

    // Seated (out of the layout) when the first reply stands right under the bubble; a date
    // line between the two keeps the label in the column and its own distances.
    private var seatsReplyCount: Bool {
        replyRowInfo.opensRun && !replyRowInfo.dateLineFollows
    }

    // Without faces the thread line runs down from the bubble's leading edge, right where
    // the label stands: the label moves in beside it.
    private var replyCountShift: CGFloat {
        guard replyRowInfo.opensRun,
              replyRowInfo.line?.bubble == .leading,
              !(messageListConfig.messageDisplayOptions.showAvatars(for: channel) || bypassGrouping) else {
            return 0
        }
        return messageListConfig.replyStyle.countShiftBesideLine
    }

    // Poppin: under the bubble. Its replies right under it: Messages' distance to the first.
    // The last reply of a run keeps Messages' distance to the message after it. And Messages
    // lets a date line that follows close up to "1 Reply": the row gives the room back (the
    // label itself cannot shrink below nothing).
    private var rowBottomPadding: CGFloat {
        let padding = showsAllInfo || isMessagePinned ? runBottomGap : bubbleBottomGap
        let style = messageListConfig.replyStyle
        if let line = replyRowInfo.line, !replyRowInfo.dateLineFollows {
            if replyRowInfo.opensRun {
                return style.gap(
                    quoteIsTrailing: line.bubble == .trailing,
                    replyIsTrailing: line.nextIsTrailing,
                    rowOpensWithName: replyRowInfo.nextOpensWithName,
                    counted: showsReplyCount
                )
            }
            if replyRowInfo.endsRun, replyRowInfo.messageFollows {
                return max(padding, style.runEndGap)
            }
        }
        guard showsReplyCount, replyRowInfo.dateLineFollows else { return padding }
        return padding - style.countTuckBeforeDate
    }

    // Extracted for the same type-checker-timeout reason as the properties above: a nested
    // `.first(where:) { if ... { .contains { ... } } else { false } }` closure inline in `body`.
    // Finds the thread-root message (if any) whose replies contain this message - used to show
    // a "replied in channel" preview above a top-level copy of a threaded reply.
    private var threadRootContainingReply: ChatMessage? {
        viewmodel.messages.first { candidate in
            guard candidate.isRootOfThread else { return false }
            return candidate.latestReplies.contains { $0.id == message.id }
        }
    }

    private var maximumHorizontalSwipeDisplacement: CGFloat {
        replyThreshold + 30
    }

    private var isMessagePinned: Bool {
        message.pinDetails != nil
    }

    // The avatar-width subtraction must mirror the body's avatar-slot
    // condition (showAvatars(for:) || bypassGrouping, line ~98) — when the
    // slot isn't rendered (e.g. DMs with avatars off), subtracting it anyway
    // would width-cap received bubbles for a slot that doesn't exist.
    private var avatarSlotWidth: CGFloat {
        guard messageListConfig.messageDisplayOptions.showAvatars(for: channel) || bypassGrouping else {
            return 0
        }
        return CGSize.messageAvatarSize.width + messageListConfig.messagePaddings.horizontal
    }

    private var contentWidth: CGFloat {
        let padding: CGFloat = messageListConfig.messagePaddings.horizontal
        let minimumWidth: CGFloat = 240
        let available = max(minimumWidth, (width ?? 0) - spacerWidth) - 2 * padding
        let totalWidth = (message.isRightAligned || factory.isSentByCurrentUser(message: message)) ? available : available - avatarSlotWidth
        return totalWidth
    }

    private var longPressContentWidth: CGFloat {
        let padding: CGFloat = messageListConfig.messagePaddings.horizontal
        let minimumWidth: CGFloat = 240
        let available = max(minimumWidth, (width ?? 0) - (spacerWidth * (4/6))) - 2 * padding
        let totalWidth = (message.isRightAligned || factory.isSentByCurrentUser(message: message)) ? available : available - avatarSlotWidth
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
        // Poppin: inside the reply view a right swipe does nothing, as in Messages: the row
        // is the thread's already, there is nothing to reply into.
        if isInThread, messageListConfig.replyThreadEnabled {
            return
        }

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
