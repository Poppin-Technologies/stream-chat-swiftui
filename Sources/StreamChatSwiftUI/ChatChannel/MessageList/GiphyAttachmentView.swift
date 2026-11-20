//
// Copyright © 2024 Stream.io Inc. All rights reserved.
//

import StreamChat
import SwiftUI

/// View for the giphy attachments.
public struct GiphyAttachmentView<Factory: ViewFactory>: View {

    @Injected(\.chatClient) private var chatClient
    @Injected(\.colors) private var colors
    @Injected(\.fonts) private var fonts
    @Injected(\.utils) private var utils

    let factory: Factory
    let message: ChatMessage
    let width: CGFloat
    let isFirst: Bool
    @Binding var scrolledId: String?

    public var body: some View {
        VStack(
            alignment: message.alignmentInBubble,
            spacing: 0
        ) {
            if let quotedMessage = utils.messageCachingUtils.quotedMessage(for: message) {
                factory.makeQuotedMessageView(
                    quotedMessage: quotedMessage,
                    fillAvailableSpace: !message.attachmentCounts.isEmpty,
                    isInComposer: false,
                    scrolledId: $scrolledId
                )
            }

            // Poppin: the row takes its final height before the GIF lands (the wire carries the
            // GIF's width and height). Without it a loading GIF was a strip that grew when its
            // file arrived, and pushed the rows under the finger.
            LazyGiphyView(
                source: message.giphyAttachments[0].previewURL,
                width: width,
                aspectRatio: giphyAspectRatio
            )
            .overlay(
                factory.makeGiphyBadgeViewType(
                    for: message,
                    availableWidth: width
                )
            )

            if !giphyActions.isEmpty {
                HStack {
                    ForEach(0..<giphyActions.count, id: \.self) { index in
                        let action = giphyActions[index]
                        Button {
                            execute(action: action)
                        } label: {
                            Text(action.value.firstUppercased)
                                .padding(.horizontal, 4)
                                .padding(.vertical)
                        }
                        .foregroundColor(
                            action.style == .primary ?
                                colors.tintColor :
                                Color(colors.textLowEmphasis)
                        )
                        .font(fonts.bodyBold)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .modifier(
            factory.makeMessageViewModifier(
                for: MessageModifierInfo(
                    message: message,
                    isFirst: isFirst
                )
            )
        )
        .frame(maxWidth: width)
        .accessibilityIdentifier("GiphyAttachmentView")
    }

    /// Poppin: width over height from the message itself, nil when the wire did not carry them.
    private var giphyAspectRatio: CGFloat? {
        let extraData = message.giphyAttachments[0].extraData
        guard let width = extraData["width"]?.numberValue, let height = extraData["height"]?.numberValue,
              width > 0, height > 0 else { return nil }
        return CGFloat(width / height)
    }

    private var giphyActions: [AttachmentAction] {
        message.giphyAttachments[0].actions
    }

    private func execute(action: AttachmentAction) {
        guard let cid = message.cid else {
            log.error("Failed to take the tap on attachment action \(action)")
            return
        }

        chatClient
            .messageController(
                cid: cid,
                messageId: message.id
            )
            .dispatchEphemeralMessageAction(action)
    }
}

public struct LazyGiphyView: View {
  
  public init(source: URL, width: CGFloat, loadingBG: Color = Color(.secondarySystemBackground), fill: Bool = false, isAnimating: Bool = true, aspectRatio: CGFloat? = nil) {
    self.source = source
    self.width = width
    self.loadingBG = loadingBG
    self.resizeMode = fill ? nil : .aspectFit
    self.isAnimating = isAnimating
    self.aspectRatio = aspectRatio
  }

  public let source: URL
  public let width: CGFloat
  public let loadingBG: Color
  private let resizeMode: ImageResizingMode?
  /// When `false`, a loaded GIF stays mounted with its display link paused
  /// (resumes mid-loop on `true`). Default preserves prior behavior.
  private let isAnimating: Bool
  /// Width over height when the caller knows it: the view then has its final size while the GIF
  /// loads. `nil` keeps the size the loaded GIF brings (every caller before 2026-11-20).
  private let aspectRatio: CGFloat?

  public var body: some View {
    LazyImage(imageURL: source) { state in
      if let imageContainer = state.imageContainer {
        NukeImage(imageContainer, resizingMode: resizeMode)
          .gifPlaybackEnabled(isAnimating)
      } else if state.error != nil {
        loadingBG
      } else {
        loadingBG
      }
    }
    .onDisappear(.cancel)
    .processors([ImageProcessors.Resize(width: width), ImageProcessors.RoundedCorners(radius: 8.0)])
    .priority(.high)
    .aspectRatio(aspectRatio, contentMode: .fit)
  }
}
