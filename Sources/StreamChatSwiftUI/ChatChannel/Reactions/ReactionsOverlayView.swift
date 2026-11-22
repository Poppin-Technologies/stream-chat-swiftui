//
// Copyright © 2024 Stream.io Inc. All rights reserved.
//

import StreamChat
import SwiftUI
import ShinySwiftUI

public struct ReactionsOverlayView<Factory: ViewFactory>: View {
    @Injected(\.utils) private var utils
    @Injected(\.colors) private var colors
    
    @StateObject var viewModel: ReactionsOverlayViewModel

    @State private var popIn = false
    @State private var willPopOut = false
    @State private var screenHeight = UIScreen.main.bounds.size.height
    /// Poppin: the ground the app covers while the chat stands in one part of the window
    /// (`chatHoldMenuCover`): the menu keeps clear of it. Zero where the chat is the window.
    @Environment(\.chatHoldMenuCover) private var cover
    @State private var screenWidth: CGFloat?
    @State private var initialWidth: CGFloat?
    @State private var orientationChanged = false
    @State private var initialOrigin: CGFloat?

    var factory: Factory
    var channel: ChatChannel
    var currentSnapshot: UIImage
    var bottomOffset: CGFloat
    var messageDisplayInfo: MessageDisplayInfo
    var onBackgroundTap: () -> Void
    var onActionExecuted: (MessageActionInfo) -> Void

    private var messageActionsCount: Int
    private let paddingValue: CGFloat = 16
    /// Poppin: one row of the menu as it is drawn: `ActionItemView` is 40 pt with 1 pt above
    /// and below it, and a hairline follows every row. Whether the menu fits is told from
    /// this, so it has to be the real height (see `messageActionsSize`).
    private var messageItemSize: CGFloat {
        42 + 1 / UIScreen.main.scale
    }
    /// Poppin: the held message never starts above this line: the reactions stand over it.
    private let minOrigin: CGFloat = 100
    /// Poppin: a message that gives way to its menu keeps at least this much height.
    private let minMessageContainerHeight: CGFloat = 160

    public init(
        factory: Factory,
        channel: ChatChannel,
        currentSnapshot: UIImage,
        messageDisplayInfo: MessageDisplayInfo,
        bottomOffset: CGFloat = 0,
        onBackgroundTap: @escaping () -> Void,
        onActionExecuted: @escaping (MessageActionInfo) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: ViewModelsFactory.makeReactionsOverlayViewModel(
                message: messageDisplayInfo.message
            )
        )
        self.channel = channel
        self.factory = factory
        self.currentSnapshot = currentSnapshot
        self.bottomOffset = bottomOffset
        self.messageDisplayInfo = messageDisplayInfo
        self.onBackgroundTap = onBackgroundTap
        self.onActionExecuted = onActionExecuted
        messageActionsCount = factory.supportedMessageActions(
            for: messageDisplayInfo.message,
            channel: channel,
            onFinish: { _ in /* No handling needed. */ },
            onError: { _ in /* No handling needed. */ }
        ).count
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                if !orientationChanged {
                    // Poppin: the snapshot is of the whole window. A chat that is one part of
                    // the window (beside the app's Chat list on the open iPhone Duo) lays it
                    // over the window's own place, so what is blurred is what stood there.
                    // The reader puts the picture at its top leading corner, where it was
                    // before; a chat that spans the window is as wide as the picture and
                    // shifts nothing.
                    GeometryReader { backdrop in
                        factory.makeReactionsBackgroundView(
                            currentSnapshot: currentSnapshot,
                            popInAnimationInProgress: !popIn
                        )
                        .offset(
                            x: backdrop.size.width < currentSnapshot.size.width - 1
                                ? -backdrop.frame(in: .global).minX : 0,
                            y: spacing > 0 ? screenHeight - currentSnapshot.size.height : 0
                        )
                    }
                } else {
                    Color.gray.opacity(0.4)
                }
            }
            .transition(.opacity)
            .onTapGesture {
                dismissReactionsOverlay() { /* No additional handling. */ }
            }
            .edgesIgnoringSafeArea(.all)
            .alert(isPresented: $viewModel.errorShown) {
                Alert.defaultErrorAlert
            }

            if !messageDisplayInfo.message.isRightAligned &&
                utils.messageListConfig.messageDisplayOptions.showAvatars(for: channel) {
                factory.makeMessageAvatarView(
                    for: utils.messageCachingUtils.authorInfo(from: messageDisplayInfo.message)
                )
                .offset(
                    x: paddingValue / 2,
                    y: originY + messageContainerHeight - paddingValue + 2
                )
                .opacity(willPopOut ? 0 : 1)
            }

            GeometryReader { reader in
                let frame = reader.frame(in: .local)
                let height = frame.height
                let width = frame.width
                Color.clear.preference(key: HeightPreferenceKey.self, value: height)
                Color.clear.preference(key: WidthPreferenceKey.self, value: width)
                
                VStack(alignment: .leading) {
                    Group {
                        if messageDisplayInfo.frame.height > messageContainerHeight {
                            ScrollView {
                                MessageView(
                                    factory: factory,
                                    message: messageDisplayInfo.message,
                                    contentWidth: messageDisplayInfo.contentWidth,
                                    isFirst: messageDisplayInfo.isFirst,
                                    scrolledId: .constant(nil)
                                )
                            }
                            .frame(height: messageContainerHeight - 100)
                        } else {
                            MessageView(
                                factory: factory,
                                message: messageDisplayInfo.message,
                                contentWidth: messageDisplayInfo.contentWidth,
                                isFirst: messageDisplayInfo.isFirst,
                                scrolledId: .constant(nil)
                            )
                        }
                    }
                    .scaleEffect(popIn || willPopOut ? 1 : 0.95)
                    .animation(willPopOut ? easeInOutAnimation : popInAnimation, value: popIn)
                    .offset(
                        x: messageOriginX(proxy: reader)
                    )
                    .overlay(
                        (channel.config.reactionsEnabled && !messageDisplayInfo.message.isBounced) ?
                            factory.makeReactionsContentView(
                                message: viewModel.message,
                                contentRect: messageDisplayInfo.frame,
                                onReactionTap: { reaction in
                                    dismissReactionsOverlay {
                                        viewModel.reactionTapped(reaction)
                                    }
                                }
                            )
                            .scaleEffect(popIn ? 1 : 0)
                            .opacity(willPopOut ? 0 : 1)
                            .animation(willPopOut ? easeInOutAnimation : popInAnimation, value: popIn)
                            .offset(
                              x: messageDisplayInfo.message.isRightAligned ? max(messageOriginX(proxy: reader), 110) : min( messageOriginX(proxy: reader), 20),
                                y: popIn ? -24 : -messageContainerHeight / 2
                            )
                            .accessibilityElement(children: .contain)
                            : nil
                    )
                    .frame(
                        width: messageDisplayInfo.frame.width,
                        height: messageContainerHeight
                    )
                    .accessibilityIdentifier("ReactionsMessageView")

                    if messageDisplayInfo.showsMessageActions {
                        factory.makeMessageActionsView(
                            for: messageDisplayInfo.message,
                            channel: channel,
                            onFinish: { actionInfo in
                                onActionExecuted(actionInfo)
                            },
                            onError: { _ in
                                viewModel.errorShown = true
                            }
                        )
                        .frame(width: messageActionsWidth)
                        .offset(
                            x: messageActionsOffsetX(reader: reader),
                            y: popIn ? 0 : -messageActionsSize / 2
                        )
                        .padding(.top, paddingValue)
                        .opacity(willPopOut ? 0 : 1)
                        .scaleEffect(popIn ? 1 : (willPopOut ? 0.4 : 0))
                        .animation(willPopOut ? easeInOutAnimation : popInAnimation, value: popIn)
                    } else if messageDisplayInfo.showsBottomContainer {
                        factory.makeReactionsUsersView(
                            message: viewModel.message,
                            maxHeight: userReactionsHeight
                        )
                        .frame(maxWidth: maxUserReactionsWidth(availableWidth: (reader.size.width - cover.trailing)))
                        .offset(
                            x: userReactionsOriginX(availableWidth: (reader.size.width - cover.trailing))
                        )
                        .padding(.top, messageDisplayInfo.message.isSentByCurrentUser ? paddingValue : 2 * paddingValue)
                        .padding(.trailing, paddingValue)
                        .scaleEffect(popIn ? 1 : 0)
                        .opacity(willPopOut ? 0 : 1)
                        .animation(willPopOut ? easeInOutAnimation : popInAnimation, value: popIn)
                    }
                }
                .offset(y: !popIn ? (messageDisplayInfo.frame.origin.y - spacing) : originY)
                .onAppear {
                    self.initialOrigin = messageDisplayInfo.frame.origin.x - diffWidth(proxy: reader)
                }
            }
        }
        .onPreferenceChange(HeightPreferenceKey.self) { value in
            if let value = value, value != screenHeight {
                self.screenHeight = value
            }
        }
        .onPreferenceChange(WidthPreferenceKey.self) { value in
            if initialWidth == nil {
                initialWidth = value
            }
            self.screenWidth = value
        }
        .edgesIgnoringSafeArea(.all)
        .background(orientationChanged ? nil : Color(colors.background))
        .onAppear {
            popIn = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ReactionsOverlayView")
        .onRotate { _ in
            if isIPad {
                self.orientationChanged = true
            }
        }
    }

    private func dismissReactionsOverlay(completion: @escaping () -> Void) {
        withAnimation {
            willPopOut = true
            popIn = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onBackgroundTap()
            completion()
        }
    }

    private func messageActionsOffsetX(reader: GeometryProxy) -> CGFloat {
        let originX = messageActionsOriginX(availableWidth: (reader.size.width - cover.trailing))
        if popIn {
            return originX
        } else if willPopOut {
            return messageOriginX(proxy: reader)
        } else {
          return messageDisplayInfo.message.isRightAligned ? messageActionsWidth : 0
        }
    }
        
    private func messageOriginX(proxy: GeometryProxy) -> CGFloat {
        let origin = messageDisplayInfo.frame.origin.x - diffWidth(proxy: proxy)
        if let initialWidth, let initialOrigin, let screenWidth, abs(initialWidth - screenWidth) > 5 {
            let diff = initialWidth - initialOrigin
            let newOrigin = screenWidth - diff
            return newOrigin
        }
        return initialOrigin ?? origin
    }

    private var messageContainerHeight: CGFloat {
        let maxAllowed = screenHeight / 2 - topSafeArea
        let containerHeight = messageDisplayInfo.frame.height
        let height = containerHeight > maxAllowed ? maxAllowed : containerHeight
        guard messageDisplayInfo.showsMessageActions else { return height }
        // Poppin: a tall message gives way to a long menu (it scrolls in what is left), so the
        // menu's last row stays on the screen while the message keeps its top line.
        let room = lowestMenuBottom - minOrigin - messageActionsGap - messageActionsSize
        return min(height, max(room, minMessageContainerHeight))
    }

    private var easeInOutAnimation: Animation {
      .slickEaseOut
    }
  
    private var popInAnimation: Animation {
        .spring(response: 0.2, dampingFraction: 0.7, blendDuration: 0.2)
    }

    private var userReactionsHeight: CGFloat {
        let reactionsCount = viewModel.message.latestReactions.count
        if reactionsCount > 4 {
            return 280
        } else {
            return 140
        }
    }

    private var originY: CGFloat {
        let bottomPopupOffset =
            messageDisplayInfo.showsMessageActions ? usualMessageActionsAllowance : userReactionsPopupHeight
        var originY = messageDisplayInfo.frame.origin.y
        var maxOrigin: CGFloat = screenHeight - cover.bottom - messageContainerHeight - bottomPopupOffset - minOrigin - bottomOffset
        if messageDisplayInfo.showsMessageActions {
            // Poppin: a menu longer than its usual place allows for ends on the lowest line
            // its last row may end on, never under it.
            let lowestOrigin = lowestMenuBottom - messageContainerHeight - messageActionsGap - messageActionsSize
            maxOrigin = min(maxOrigin, lowestOrigin)
        }
        if originY < minOrigin {
            originY = minOrigin
        } else if originY > maxOrigin {
            originY = maxOrigin
        }
        
        return originY - spacing
    }
    
    private var spacing: CGFloat {
        let divider: CGFloat = isIPad ? 2 : 1
        let spacing = (UIScreen.main.bounds.height - screenHeight) / divider
        return spacing > 0 ? spacing : 0
    }

    /// Poppin: the menu's real height. Its place used to come from `usualMessageActionsAllowance`
    /// alone: from the eighth row on the menu was taller than that, and an admin's ninth row
    /// ended under the screen's edge (2026-11-22).
    private var messageActionsSize: CGFloat {
        messageItemSize * CGFloat(messageActionsCount)
    }

    /// Poppin: what the menu's usual place allows for it: 40 pt a row, a third of the screen at
    /// most. It is kept as it always was, so a menu that fits stands where it always stood; a
    /// longer one ends on `lowestMenuBottom`.
    private var usualMessageActionsAllowance: CGFloat {
        min(40 * CGFloat(messageActionsCount), screenHeight / 3)
    }

    /// Poppin: what stands between the message and its menu: the stack's spacing and the
    /// menu's top padding.
    private var messageActionsGap: CGFloat {
        8 + paddingValue
    }

    /// Poppin: the lowest line the menu's last row may end on: clear of covered ground and of
    /// the home bar's strip, and never tight against the screen's edge.
    private var lowestMenuBottom: CGFloat {
        screenHeight - max(cover.bottom, bottomSafeArea, 12) - bottomOffset - 8
    }

    private var userReactionsPopupHeight: CGFloat {
        userReactionsHeight + 3 * paddingValue
    }

    /// Poppin: the overlay's own left edge in the window, on every device (it was the iPad's
    /// alone). 0 where the chat spans the window; the part's edge where the chat stands
    /// beside the app's Chat list on the open iPhone Duo, so the held message keeps its place.
    private func diffWidth(proxy: GeometryProxy) -> CGFloat {
        proxy.frame(in: .global).minX
    }

    private func maxUserReactionsWidth(availableWidth: CGFloat) -> CGFloat {
        availableWidth - 2 * paddingValue
    }

    private func messageActionsOriginX(availableWidth: CGFloat) -> CGFloat {
        if messageDisplayInfo.message.isRightAligned {
            return availableWidth - messageActionsWidth - paddingValue / 2
        } else {
            return CGSize.messageAvatarSize.width + paddingValue
        }
    }

    private func userReactionsOriginX(availableWidth: CGFloat) -> CGFloat {
        if messageDisplayInfo.message.isRightAligned {
            return availableWidth - maxUserReactionsWidth(availableWidth: availableWidth) - paddingValue / 2
        } else {
            return paddingValue
        }
    }

    private var messageActionsWidth: CGFloat {
        var width = messageDisplayInfo.contentWidth + 2 * paddingValue
        if messageDisplayInfo.message.isRightAligned {
            width -= 2 * paddingValue
        }

        return width
    }
}

struct DeviceRotationViewModifier: ViewModifier {
    let action: (UIDeviceOrientation) -> Void

    func body(content: Content) -> some View {
        content
            .onAppear()
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                action(UIDevice.current.orientation)
            }
    }
}

extension View {
    func onRotate(perform action: @escaping (UIDeviceOrientation) -> Void) -> some View {
        modifier(DeviceRotationViewModifier(action: action))
    }
}
