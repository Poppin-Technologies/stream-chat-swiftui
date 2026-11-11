//
// Copyright © 2024 Stream.io Inc. All rights reserved.
//

import StreamChat
import SwiftUI
import ShinySwiftUI

/// View for the chat channel.
public struct ChatChannelView<Factory: ViewFactory>: View, KeyboardReadable {
    @Injected(\.colors) private var colors
    @Injected(\.utils) private var utils
    @Injected(\.chatClient) private var chatClient

    @StateObject private var viewModel: ChatChannelViewModel

    @Environment(\.presentationMode) var presentationMode

    @State private var messageDisplayInfo: MessageDisplayInfo?
    @State private var keyboardShown = false
    @State private var tabBarAvailable: Bool = false

    private var factory: Factory

    public init(
        viewFactory: Factory = DefaultViewFactory.shared,
        viewModel: ChatChannelViewModel? = nil,
        channelController: ChatChannelController,
        messageController: ChatMessageController? = nil,
        scrollToMessage: ChatMessage? = nil,
        chatTheme: Appearance? = nil
    ) {
        if let chatTheme {
          InjectedValues[\.streamChat].appearance.customized = chatTheme
        }
        _viewModel = StateObject(
            wrappedValue: viewModel ?? ViewModelsFactory.makeChannelViewModel(
                with: channelController,
                messageController: messageController,
                scrollToMessage: scrollToMessage
            )
        )
        factory = viewFactory
    }

    public var body: some View {
        ZStack(alignment: .top) {
            if let channel = viewModel.channel {
                factory.makeChannelHeader(channel: channel, viewmodel: viewModel)
                  .zIndex(99)
                VStack(spacing: 0) {
                    factory.makeChannelTopBar(channel: channel)
                    // Poppin: with composerOverlaysList the composer is a bottom safe-area inset
                    // of the conversation, not a sibling below it — the list extends under the
                    // bar (which frosts the bubbles sliding beneath it, like Messages) and
                    // MessageListView reserves the bar's live height (keyboard, quoted header,
                    // attachment tray) at its visual bottom.
                    if overlaysComposer {
                        if #available(iOS 15.0, *) {
                            conversationArea(for: channel)
                                .safeAreaInset(edge: .bottom, spacing: 0) {
                                    composerView
                                }
                        } else {
                            conversationArea(for: channel)
                        }
                    } else {
                        conversationArea(for: channel)
                    }

                    Text("")
                        .navigationBarTitleDisplayMode(.inline)
                        .frame(width: 0, height: 0)
                        .fixedSize()
                        .navigationBarBackButtonHidden(viewModel.reactionsShown)
                        .if(viewModel.reactionsShown, transform: { view in
                            view.navigationBarHidden(true)
                        })
                        .if(viewModel.reactionsShown, transform: { view in
                            view.navigationBarHidden(true)
                        })
                        .if(!viewModel.reactionsShown, transform: { view in
                            view.navigationBarHidden(false)
                        })
                        .if(viewModel.channelHeaderType == .messageThread) { view in
                            view.modifier(factory.makeMessageThreadHeaderViewModifier())
                        }
                        .animation(nil)

                    if !overlaysComposer {
                        composerView
                            .padding(.top, -4)
                    }

                    NavigationLink(
                        isActive: $viewModel.threadMessageShown
                    ) {
                        if let message = viewModel.threadMessage {
                            let threadDestination = factory.makeMessageThreadDestination()
                            threadDestination(channel, message)
                        } else {
                            EmptyView()
                        }
                    } label: {
                        EmptyView()
                    }
                }
                .accentColor(colors.tintColor)
                .overlay(
                    viewModel.reactionsShown ?
                        factory.makeReactionsOverlayView(
                            channel: channel,
                            currentSnapshot: viewModel.currentSnapshot!,
                            messageDisplayInfo: messageDisplayInfo!,
                            onBackgroundTap: {
                                viewModel.reactionsShown = false
                                if messageDisplayInfo?.keyboardWasShown == true {
                                    becomeFirstResponder()
                                }
                                messageDisplayInfo = nil
                            }, onActionExecuted: { actionInfo in
                                viewModel.messageActionExecuted(actionInfo)
                                messageDisplayInfo = nil
                            }
                        )
                        .transition(.identity)
                        .edgesIgnoringSafeArea(.all)
                        : nil
                )
                .background(
                    factory.makeMessageListBackground(
                        colors: colors,
                        isInThread: false
                    )
                )
            } else if let failure = viewModel.channelLoadFailure {
                // Copy per failure (offline / busy / cooldown / generic); Retry for every case.
                VStack(spacing: 12) {
                    Text(failure.title)
                        .foregroundColor(Color(colors.textLowEmphasis))
                    if let subtitle = failure.subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundColor(Color(colors.textLowEmphasis))
                            .multilineTextAlignment(.center)
                    }
                    Button {
                        viewModel.retryChannelLoad()
                    } label: {
                        Text("Retry")
                            .bold()
                            .foregroundColor(colors.tintColor)
                    }
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                factory.makeChannelLoadingView()
            }
        }
        .edgesIgnoringSafeArea(.top)
        .navigationBarTitleDisplayMode(factory.navigationBarDisplayMode())
        .onReceive(keyboardWillChangePublisher, perform: { visible in
            keyboardShown = visible
        })
        .onAppear {
            viewModel.onViewAppear()
            if utils.messageListConfig.becomesFirstResponderOnOpen {
                keyboardShown = true
            }
        }
        .onDisappear {
            viewModel.onViewDissappear()
        }
        .navigationBarHidden(true)
        .onChange(of: presentationMode.wrappedValue, perform: { newValue in
            if newValue.isPresented == false {
                viewModel.onViewDissappear()
            } else {
                viewModel.setActive()
            }
        })
        .background(
            isIphone ?
                Color.clear.background(
                    TabBarAccessor { _ in
                        self.tabBarAvailable = utils.messageListConfig.handleTabBarVisibility
                    }
                )
                .allowsHitTesting(false)
                : nil
        )
        .padding(.bottom, keyboardShown || !tabBarAvailable || generatingSnapshot ? 0 : bottomPadding)
        .ignoresSafeArea(.container, edges: tabBarAvailable ? .bottom : [])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ChatChannelView")
        .environmentObject(viewModel)
    }

    // MARK: - Poppin: conversation + composer pieces

    /// True when the composer overlays the list (`safeAreaInset` is iOS 15+).
    private var overlaysComposer: Bool {
        if #available(iOS 15.0, *) {
            return utils.messageListConfig.composerOverlaysList
        }
        return false
    }

    @ViewBuilder
    private func conversationArea(for channel: ChatChannel) -> some View {
        if !viewModel.messages.isEmpty {
            MessageListView(
                factory: factory,
                channel: channel,
                messages: viewModel.messages,
                messagesGroupingInfo: viewModel.messagesGroupingInfo,
                scrolledId: $viewModel.scrolledId,
                showScrollToLatestButton: $viewModel.showScrollToLatestButton,
                quotedMessage: $viewModel.quotedMessage,
                currentDateString: viewModel.currentDateString,
                listId: viewModel.listId,
                isMessageThread: viewModel.isMessageThread,
                shouldShowTypingIndicator: viewModel.shouldShowTypingIndicator,
                scrollPosition: $viewModel.scrollPosition,
                loadingNextMessages: viewModel.loadingNextMessages,
                onMessageAppear: viewModel.handleMessageAppear(index:scrollDirection:),
                onScrollToBottom: viewModel.scrollToLastMessage,
                onLongPress: { displayInfo in
                    messageDisplayInfo = displayInfo
                    withAnimation {
                        viewModel.showReactionOverlay(for: AnyView(self))
                    }
                },
                onJumpToMessage: viewModel.jumpToMessage(messageId:)
            )
            .modifier(ReplyBackdropModifier(
                enabled: utils.messageListConfig.replyThreadEnabled,
                covered: replyThreadShown,
                radius: utils.messageListConfig.replyStyle.backdropBlurRadius
            ))
            .overlay(
                viewModel.currentDateString != nil ?
                    factory.makeDateIndicatorView(dateString: viewModel.currentDateString!)
                    : nil
            )
            .overlay(replyThreadOverlay(for: channel))
        } else {
            ZStack {
                factory.makeEmptyMessagesView(for: channel, colors: colors)
                if viewModel.shouldShowTypingIndicator {
                    factory.makeTypingIndicatorBottomView(
                        channel: channel,
                        currentUserId: chatClient.currentUserId
                    )
                }
            }
        }
    }

    /// Poppin: while a reply is being written the conversation gives way to that thread
    /// (Messages). It covers the list only: the composer stays above it, the header over it.
    private var replyThreadShown: Bool {
        utils.messageListConfig.replyThreadEnabled && viewModel.quotedMessage != nil
    }

    @ViewBuilder
    private func replyThreadOverlay(for channel: ChatChannel) -> some View {
        if replyThreadShown {
            factory.makeReplyThreadView(
                channel: channel,
                viewModel: viewModel,
                onLongPress: { displayInfo in
                    // As the list does for its own rows: the keyboard steps down for the menu
                    // and comes back when the menu closes.
                    var displayInfo = displayInfo
                    if keyboardShown {
                        resignFirstResponder()
                        displayInfo.keyboardWasShown = true
                    }
                    messageDisplayInfo = displayInfo
                    withAnimation {
                        viewModel.showReactionOverlay(for: AnyView(self))
                    }
                }
            )
            .transition(.opacity)
        }
    }

    private var composerView: some View {
        factory.makeMessageComposerViewType(
            with: viewModel.channelController,
            messageController: viewModel.messageController,
            quotedMessage: $viewModel.quotedMessage,
            editedMessage: $viewModel.editedMessage,
            onMessageSent: viewModel.scrollToLastMessage
        )
        .opacity((
            utils.messageListConfig.messagePopoverEnabled && messageDisplayInfo != nil && !viewModel
                .reactionsShown && viewModel.channel?.isFrozen == false
        ) ? 0 : 1)
    }

    private var generatingSnapshot: Bool {
        tabBarAvailable && messageDisplayInfo != nil && !viewModel.reactionsShown
    }

    private var bottomPadding: CGFloat {
        let bottomPadding = topVC()?.view.safeAreaInsets.bottom ?? 0
        return bottomPadding
    }
}

/// Poppin: behind the reply view the conversation is a blur of its own bubbles (Messages): a
/// real blur, so a black chat stays black, and its rows are told they are covered. With the
/// reply view off the list is left exactly as it was. `enabled` is a setting that never
/// changes while the app runs, so the branch cannot flip under a live list (a flip would
/// rebuild it); what animates is the radius.
private struct ReplyBackdropModifier: ViewModifier {
    var enabled: Bool
    var covered: Bool
    var radius: CGFloat

    func body(content: Content) -> some View {
        if enabled {
            content
                .blur(radius: covered ? radius : 0)
                .environment(\.replyViewCoversList, covered)
        } else {
            content
        }
    }
}

extension PresentationMode: Equatable {

    public static func == (lhs: PresentationMode, rhs: PresentationMode) -> Bool {
        lhs.isPresented == rhs.isPresented
    }
}
