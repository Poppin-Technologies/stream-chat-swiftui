//
// Copyright © 2024 Stream.io Inc. All rights reserved.
//

import SwiftUI
import StreamChat
import ShinySwiftUI


/// Modifier that enables message bubble container.
public struct ReactionsBubbleModifier: ViewModifier {
    @Injected(\.colors) private var colors
    @Injected(\.chatClient) private var chatClient

    var message: ChatMessage

    var borderColor: Color? = nil
    var injectedBackground: UIColor? = nil

    private let cornerRadius: CGFloat = 18

    public func body(content: Content) -> some View {
        content
        .background(
          ZStack {
            Color(backgroundColor)
            if message.currentUserReactionsCount == 0 {
              VisualEffectView()
            }
          }
        )
        .clipShape(
          BubbleBackgroundShape(
            cornerRadius: cornerRadius,
            corners: corners
          )
        )
    }

    private var corners: UIRectCorner {
        [.topLeft, .topRight, .bottomLeft, .bottomRight]
    }
  

    private var backgroundColor: UIColor {
        if let injectedBackground = injectedBackground {
            return injectedBackground
        }
        if message.currentUserReactionsCount > 0 {
          return UIColor(colors.tintColor)
        }

        if message.isSentByCurrentUser {
          return colors.background8.withAlphaComponent(0.66)
        } else {
          return colors.background6.withAlphaComponent(0.66)
        }
    }
}

extension View {
    public func reactionsBubble(for message: ChatMessage, background: UIColor? = nil) -> some View {
        modifier(ReactionsBubbleModifier(message: message, injectedBackground: background))
    }
}
