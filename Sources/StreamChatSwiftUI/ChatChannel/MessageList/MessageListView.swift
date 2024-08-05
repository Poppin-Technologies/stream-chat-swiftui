//
// Copyright © 2024 Stream.io Inc. All rights reserved.
//

import StreamChat
import SwiftUI
import ShinySwiftUI

public struct MessageListView<Factory: ViewFactory>: View, KeyboardReadable {

    @EnvironmentObject var viewModel: ChatChannelViewModel
    @Injected(\.utils) private var utils
    @Injected(\.chatClient) private var chatClient
    @Injected(\.colors) private var colors

    var factory: Factory
    var channel: ChatChannel
    var messages: LazyCachedMapCollection<ChatMessage>
    var messagesGroupingInfo: [String: [String]]
    @Binding var scrolledId: String?
    @Binding var showScrollToLatestButton: Bool
    @Binding var quotedMessage: ChatMessage?
    @Binding var scrollPosition: String?
    var loadingNextMessages: Bool
    var currentDateString: String?
    var listId: String
    var isMessageThread: Bool
    var shouldShowTypingIndicator: Bool
    
    var onMessageAppear: (Int, ScrollDirection) -> Void
    var onScrollToBottom: () -> Void
    var onLongPress: (MessageDisplayInfo) -> Void
    var onJumpToMessage: ((String) -> Bool)?
    
    @State private var width: CGFloat?
    @State private var keyboardShown = false
    @State private var pendingKeyboardUpdate: Bool?
    @State private var scrollDirection = ScrollDirection.up
    @State private var newMessagesStartId: String?
    @State private var offsetX: CGFloat = 0.0
    @GestureState private var offset: CGSize = .zero

    private var messageRenderingUtil = MessageRenderingUtil.shared
    private var skipRenderingMessageIds = [String]()

    private var dateFormatter: DateFormatter {
        utils.dateFormatter
    }

    private var messageListConfig: MessageListConfig {
        utils.messageListConfig
    }

    private var messageListDateUtils: MessageListDateUtils {
        utils.messageListDateUtils
    }

    private var lastInGroupHeaderSize: CGFloat {
        messageListConfig.messageDisplayOptions.lastInGroupHeaderSize
    }
    
    private var newMessagesSeparatorSize: CGFloat {
        messageListConfig.messageDisplayOptions.newMessagesSeparatorSize
    }

    private let scrollAreaId = "scrollArea"

    public init(
        factory: Factory,
        channel: ChatChannel,
        messages: LazyCachedMapCollection<ChatMessage>,
        messagesGroupingInfo: [String: [String]],
        scrolledId: Binding<String?>,
        showScrollToLatestButton: Binding<Bool>,
        quotedMessage: Binding<ChatMessage?>,
        currentDateString: String? = nil,
        listId: String,
        isMessageThread: Bool = false,
        shouldShowTypingIndicator: Bool = false,
        scrollPosition: Binding<String?> = .constant(nil),
        loadingNextMessages: Bool = false,
        onMessageAppear: @escaping (Int, ScrollDirection) -> Void,
        onScrollToBottom: @escaping () -> Void,
        onLongPress: @escaping (MessageDisplayInfo) -> Void,
        onJumpToMessage: ((String) -> Bool)? = nil
    ) {
        self.factory = factory
        self.channel = channel
        self.messages = messages
        self.messagesGroupingInfo = messagesGroupingInfo
        self.currentDateString = currentDateString
        self.listId = listId
        self.isMessageThread = isMessageThread
        self.onMessageAppear = onMessageAppear
        self.onScrollToBottom = onScrollToBottom
        self.onLongPress = onLongPress
        self.onJumpToMessage = onJumpToMessage
        self.shouldShowTypingIndicator = shouldShowTypingIndicator
        self.loadingNextMessages = loadingNextMessages
        _scrolledId = scrolledId
        _showScrollToLatestButton = showScrollToLatestButton
        _quotedMessage = quotedMessage
        _scrollPosition = scrollPosition
        if !messageRenderingUtil.hasPreviousMessageSet
            || self.showScrollToLatestButton == false
            || self.scrolledId != nil
            || messages.first != nil ? factory.isSentByCurrentUser(message: messages.first!) : false {
            messageRenderingUtil.update(previousTopMessage: messages.first)
        }
        skipRenderingMessageIds = messageRenderingUtil.messagesToSkipRendering(newMessages: messages)
        if !skipRenderingMessageIds.isEmpty {
            self.messages = LazyCachedMapCollection(
                source: messages.filter { !skipRenderingMessageIds.contains($0.id) },
                map: { $0 }
            )
        }
        if messageListConfig.showNewMessagesSeparator && channel.unreadCount.messages > 0 {
            let index = channel.unreadCount.messages - 1
            if index < messages.count {
                _newMessagesStartId = .init(wrappedValue: messages[index].id)
            }
        } else {
            _newMessagesStartId = .init(wrappedValue: nil)
        }
    }

    public var body: some View {
        ZStack {
            ScrollViewReader { scrollView in
                ScrollView {
                    GeometryReader { proxy in
                        let frame = proxy.frame(in: .named(scrollAreaId))
                        let offset = frame.minY
                        let width = frame.width
                        Color.clear.preference(key: ScrollViewOffsetPreferenceKey.self, value: offset)
                        Color.clear.preference(key: WidthPreferenceKey.self, value: width)
                    }

                    LazyVStack(spacing: 0) {
                      ForEach(viewModel.messages, id: \.messageId) { message in
                            var index: Int? = messageListDateUtils.indexForMessageDate(message: message, in: messages)
                            let messageDate: Date? = messageListDateUtils.showMessageDate(for: index, in: messages)
                            let showUnreadSeparator = message.id == newMessagesStartId
                            let showsLastInGroupInfo = showsLastInGroupInfo(for: message, channel: channel)
                          VStack(spacing: 4) {
                            if let m = viewModel.messageWithDates[message.id] {
                              formatDate(date: m).font(.footnote)
                                .padding(.vertical, 8)
                                .foregroundColor(Color(colors.textLowEmphasis))
                            }
                            factory.makeMessageContainerView(
                              channel: channel,
                              message: message,
                              width: width,
                              showsAllInfo: showsAllData(for: message),
                              isInThread: isMessageThread,
                              scrolledId: $scrolledId,
                              quotedMessage: $quotedMessage,
                              onLongPress: handleLongPress(messageDisplayInfo:),
                              isLast: !showsLastInGroupInfo && message == messages.last,
                              isLastGroup: showsFirstData(for: message),
                              optionalOffset: $offsetX
                            )
                            .onAppear {
                              if index == nil {
                                index = messageListDateUtils.index(for: message, in: viewModel.messages)
                              }
                              if let index = index {
                                onMessageAppear(index, scrollDirection)
                              }
                              utils.isSentByCurrentUser = factory.isSentByCurrentUser
                              utils.isAnon = factory.isFirst
                            }
                            .onAppear() {
                              utils.isAnonModeOn = { c in
                                factory.isAnonModeOn(channel: c)
                              }
                            }
                            .padding(
                              .top,
                              messageDate != nil ?
                              offsetForDateIndicator(
                                showsLastInGroupInfo: showsLastInGroupInfo,
                                showUnreadSeparator: showUnreadSeparator
                              ) :
                                additionalTopPadding(
                                  showsLastInGroupInfo: showsLastInGroupInfo,
                                  showUnreadSeparator: showUnreadSeparator
                                )
                            )
                            .overlay(
                              (messageDate != nil || showsLastInGroupInfo || showUnreadSeparator) ?
                              VStack(spacing: 0) {
                                messageDate != nil ?
                                factory.makeMessageListDateIndicator(date: messageDate!)
                                  .frame(maxHeight: messageListConfig.messageDisplayOptions.dateLabelSize)
                                : nil
                                
                                showUnreadSeparator ?
                                factory.makeNewMessagesIndicatorView(
                                  newMessagesStartId: $newMessagesStartId,
                                  count: newMessagesCount(for: index, message: message)
                                )
                                : nil
                                
                                showsLastInGroupInfo ?
                                factory.makeLastInGroupHeaderView(for: message)
                                  .frame(maxHeight: lastInGroupHeaderSize)
                                : nil
                                
                                Spacer()
                              }
                              : nil
                            )
                            .offset(x: max(offsetX, -55))
                            .animation(nil, value: messageDate != nil)
                          }
                          .flippedUpsideDown()

                        }
                        .id(listId)
                    }
                    .modifier(factory.makeMessageListModifier())
                    .modifier(ScrollTargetLayoutModifier(enabled: loadingNextMessages))
                }
                .if(true) { view in
                  Group {
                    if #available(iOS 16.0, *) {
                      view
                        .scrollDismissesKeyboard(.immediately)
                    } else {
                      view
                    }
                  }
                }
                .modifier(ScrollPositionModifier(scrollPosition: loadingNextMessages ? $scrollPosition : .constant(nil)))
                .coordinateSpace(name: scrollAreaId)
                .onPreferenceChange(WidthPreferenceKey.self) { value in
                    if let value = value, value != width {
                        self.width = value
                    }
                }
                .onPreferenceChange(ScrollViewOffsetPreferenceKey.self) { value in
                    DispatchQueue.main.async {
                        let offsetValue = value ?? 0
                        let diff = offsetValue - utils.messageCachingUtils.scrollOffset
                        if abs(diff) > 15 {
                            if diff > 0 {
                                if scrollDirection == .up {
                                    scrollDirection = .down
                                }
                            } else if diff < 0 && scrollDirection == .down {
                                scrollDirection = .up
                            }
                        }
                        utils.messageCachingUtils.scrollOffset = offsetValue
                        let scrollButtonShown = offsetValue < -20
                        if scrollButtonShown != showScrollToLatestButton {
                            showScrollToLatestButton = scrollButtonShown
                        }
                        if keyboardShown && diff < -20 {
                            keyboardShown = false
                            resignFirstResponder()
                        }
                        if offsetValue > 5 {
                            onMessageAppear(0, .down)
                        }
                    }
                }
                .simultaneousGesture(
                    DragGesture(
                        minimumDistance: 10,
                        coordinateSpace: .global
                    )
                    .updating($offset) { (value, gestureState, _) in
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
                  if !(offset == .zero && self.offsetX == .zero) {
                    withAnimation(.interpolatingSpring(stiffness: 170, damping: 20)) {
                      if offset == .zero {
                        self.offsetX = 0
                      } else {
                        dragChanged(to: offset.width)
                      }
                    }
                  }
                })
                .flippedUpsideDown()
                .frame(maxWidth: .infinity)
                .clipped()
                .onChange(of: scrolledId) { scrolledId in
                    if let scrolledId = scrolledId {
                        let shouldJump = onJumpToMessage?(scrolledId) ?? false
                        if !shouldJump {
                            return
                        }
                        withAnimation {
                            scrollView.scrollTo(scrolledId, anchor: messageListConfig.scrollingAnchor)
                        }
                    }
                }
                .accessibilityIdentifier("MessageListScrollView")
            }

            if showScrollToLatestButton {
                factory.makeScrollToBottomButton(
                    unreadCount: channel.unreadCount.messages,
                    onScrollToBottom: onScrollToBottom
                )
            }

            if shouldShowTypingIndicator {
                factory.makeTypingIndicatorBottomView(
                    channel: channel,
                    currentUserId: chatClient.currentUserId
                )
            }
        }
        .onChange(of: messages.count) { m in
          print(messages.first?.text)
        }

        .onReceive(keyboardDidChangePublisher) { visible in
            if currentDateString != nil {
                pendingKeyboardUpdate = visible
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    keyboardShown = visible
                }
            }
        }
        .onChange(of: currentDateString, perform: { dateString in
            if dateString == nil, let keyboardUpdate = pendingKeyboardUpdate {
                keyboardShown = keyboardUpdate
                pendingKeyboardUpdate = nil
            }
        })
        .modifier(factory.makeMessageListContainerModifier())
        .modifier(HideKeyboardOnTapGesture(shouldAdd: keyboardShown))
        .simultaneousGesture(TapGesture().onEnded({ _ in
          NotificationCenter.default.post(Notification(name: .init(rawValue: Constants.photoPickerDropDown)))
        }))
        .onDisappear {
            messageRenderingUtil.update(previousTopMessage: nil)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("MessageListView")
    }

    private func additionalTopPadding(showsLastInGroupInfo: Bool, showUnreadSeparator: Bool) -> CGFloat {
        var padding = showsLastInGroupInfo ? lastInGroupHeaderSize : 0
        if showUnreadSeparator {
            padding += newMessagesSeparatorSize
        }
        return padding
    }

    private func offsetForDateIndicator(showsLastInGroupInfo: Bool, showUnreadSeparator: Bool) -> CGFloat {
        var offset = messageListConfig.messageDisplayOptions.dateLabelSize
        offset += additionalTopPadding(showsLastInGroupInfo: showsLastInGroupInfo, showUnreadSeparator: showUnreadSeparator)
        return offset
    }
    
    private func newMessagesCount(for index: Int?, message: ChatMessage) -> Int {
        if let index = index {
            return index + 1
        } else if let index = messageListDateUtils.index(for: message, in: messages) {
            return index + 1
        } else {
            return channel.unreadCount.messages
        }
    }

    private func showsAllData(for message: ChatMessage) -> Bool {
        if !messageListConfig.groupMessages {
            return true
        }
        let groupInfo = messagesGroupingInfo[message.id] ?? []
        return groupInfo.contains(firstMessageKey) == true
    }
  
    private func showsFirstData(for message: ChatMessage) -> Bool {
        if !messageListConfig.groupMessages {
            return true
        }
        let groupInfo = messagesGroupingInfo[message.id] ?? []
        return groupInfo.contains(lastMessageKey) == true || factory.isFirst(message: message)
    }

    private func showsLastInGroupInfo(
        for message: ChatMessage,
        channel: ChatChannel
    ) -> Bool {
        guard channel.memberCount > 2
            && !message.isSentByCurrentUser
            && (lastInGroupHeaderSize > 0) else {
            return false
        }
        let groupInfo = messagesGroupingInfo[message.id] ?? []
        return groupInfo.contains(lastMessageKey) == true
    }

    private func handleLongPress(messageDisplayInfo: MessageDisplayInfo) {
        if keyboardShown {
            resignFirstResponder()
            let updatedFrame = CGRect(
                x: messageDisplayInfo.frame.origin.x,
                y: messageDisplayInfo.frame.origin.y,
                width: messageDisplayInfo.frame.width,
                height: messageDisplayInfo.frame.height
            )

            let updatedDisplayInfo = MessageDisplayInfo(
                message: messageDisplayInfo.message,
                frame: updatedFrame,
                contentWidth: messageDisplayInfo.contentWidth,
                isFirst: messageDisplayInfo.isFirst,
                keyboardWasShown: true
            )

            onLongPress(updatedDisplayInfo)
        } else {
            onLongPress(messageDisplayInfo)
        }
    }
  
    private func dragChanged(to value: CGFloat) {
        let horizontalTranslation = value

        
        if horizontalTranslation <= -10 {
            offsetX = horizontalTranslation
        } else {
            offsetX = 0
        }
    }
    func formatDate(date: Date) -> Text {
        let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter
        }()
        
        let timeFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter
        }()
        let now = Date()
        
        if Calendar.current.isDateInToday(date) {
            return Text("**Today** \(timeFormatter.string(from: date))")
        } else if Calendar.current.isDateInYesterday(date) {
            return Text("**Yesterday** \(timeFormatter.string(from: date))")
        } else if Calendar.current.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            return Text("**\(dateFormatter.string(from: date))** \(timeFormatter.string(from: date))")
        } else {
          let formatter = DateFormatter()
          formatter.dateFormat = "E, MMM d"
          return Text("**\(formatter.string(from: date))**, \(timeFormatter.string(from: date))")
        }
    }
}

struct ScrollPositionModifier: ViewModifier {
    @Binding var scrollPosition: String?
    
    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content
                .scrollPosition(id: $scrollPosition, anchor: .top)
        } else {
            content
        }
    }
}

struct ScrollTargetLayoutModifier: ViewModifier {
    
    var enabled: Bool
    
    func body(content: Content) -> some View {
        if !enabled {
            return content
        }
        if #available(iOS 17, *) {
            return content
                .scrollTargetLayout(isEnabled: enabled)
                .scrollTargetBehavior(.paging)
        } else {
            return content
        }
    }
}

public enum ScrollDirection {
    case up
    case down
}

public struct NewMessagesIndicator: View {
            
    @Injected(\.colors) var colors
    
    @Binding var newMessagesStartId: String?
    var count: Int
    
    public init(newMessagesStartId: Binding<String?>, count: Int) {
        _newMessagesStartId = newMessagesStartId
        self.count = count
    }
    
    public var body: some View {
        HStack {
            Text("\(L10n.MessageList.newMessages(count))")
                .foregroundColor(Color(colors.textLowEmphasis))
                .font(.system(size: 12))
                .padding(.all)
        }
        .background(
          ZStack {
            Color(colors.background8).opacity(0.33)
            VisualEffectView()
          }
        )
        .clipShape(Capsule())
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .onDisappear {
            newMessagesStartId = nil
        }
    }
}

public struct ScrollToBottomButton: View {
    @Injected(\.images) private var images
    @Injected(\.colors) private var colors

    private let buttonSize: CGFloat = 40

    var unreadCount: Int
    var onScrollToBottom: () -> Void

    public var body: some View {
        BottomRightView {
            Button {
                onScrollToBottom()
            } label: {
                Image(systemName: "chevron.down")
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: buttonSize, height: buttonSize)
                    .modifier(ShadowViewModifier(cornerRadius: buttonSize / 2))
                    .foregroundColor(colors.tintColor)
            }
            .padding()
            .overlay(
                unreadCount > 0 ?
                    UnreadButtonIndicator(unreadCount: unreadCount) : nil
            )
        }
        .accessibilityIdentifier("ScrollToBottomButton")
    }
}

struct UnreadButtonIndicator: View {
    @Injected(\.colors) private var colors
    @Injected(\.fonts) private var fonts

    private let size: CGFloat = 16

    var unreadCount: Int

    var body: some View {
        Text("\(unreadCount)")
            .lineLimit(1)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .font(fonts.footnoteBold)
            .frame(width: unreadCount < 10 ? size : nil, height: size)
            .padding(.horizontal, unreadCount < 10 ? 2 : 6)
            .background(Color(colors.highlightedAccentBackground))
            .cornerRadius(9)
            .foregroundColor(Color(colors.staticColorText))
            .offset(y: -size)
    }
}

public struct DateIndicatorView: View {
    @Injected(\.colors) private var colors
    @Injected(\.fonts) private var fonts

    var dateString: String

    public init(date: Date) {
        dateString = DateFormatter.messageListDateOverlay.string(from: date)
    }

    public init(dateString: String) {
        self.dateString = dateString
    }

    public var body: some View {
        VStack {
            Text(dateString)
                .font(fonts.footnote)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .foregroundColor(.white)
                .background(Color(colors.textLowEmphasis))
                .cornerRadius(16)
                .padding(.all, 8)
            Spacer()
        }
    }
}

struct TypingIndicatorBottomView: View {
    @Injected(\.colors) private var colors
    @Injected(\.fonts) private var fonts

    var typingIndicatorString: String

    var body: some View {
        VStack {
            Spacer()
            HStack {
                TypingIndicatorView()
                Text(typingIndicatorString)
                    .font(.footnote)
                    .foregroundColor(Color(colors.textLowEmphasis))
                Spacer()
            }
            .standardPadding()
            .background(
                Color(colors.background)
                    .opacity(0.3)
            )
            .transition(.swipeUp.animation(.slickEaseIn(duration: 0.3)))
            .accessibilityIdentifier("TypingIndicatorBottomView")
        }
        .accessibilityElement(children: .contain)
    }
}

private class MessageRenderingUtil {

    private var previousTopMessage: ChatMessage?

    static let shared = MessageRenderingUtil()

    var hasPreviousMessageSet: Bool {
        previousTopMessage != nil
    }

    func update(previousTopMessage: ChatMessage?) {
        self.previousTopMessage = previousTopMessage
    }

    func messagesToSkipRendering(newMessages: LazyCachedMapCollection<ChatMessage>) -> [String] {
        let newTopMessage = newMessages.first
        if newTopMessage?.id == previousTopMessage?.id {
            return []
        }

        if newTopMessage?.cid != previousTopMessage?.cid {
            previousTopMessage = newTopMessage
            return []
        }

        var skipRendering = [String]()
        for message in newMessages {
            if previousTopMessage?.id == message.id {
                break
            } else {
                skipRendering.append(message.id)
            }
        }

        return skipRendering
    }
}
