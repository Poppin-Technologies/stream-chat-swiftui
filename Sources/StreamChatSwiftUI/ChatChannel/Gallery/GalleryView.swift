//
// Copyright © 2024 Stream.io Inc. All rights reserved.
//

import StreamChat
import SwiftUI

/// View used for displaying image attachments in a gallery.
///
/// Poppin (2026-11-21): the look of Messages' photo viewer. Black, "2 of 8" on top with the grid
/// button and Done, Share bottom left, Reply bottom right, a pull down closes. The grid is the
/// viewer's second face (`GridPhotosView`), not a sheet on top of it.
public struct GalleryView: View {

    @Environment(\.presentationMode) var presentationMode

    @Injected(\.colors) private var colors
    @Injected(\.fonts) private var fonts
    @Injected(\.images) private var images

    var imageAttachments: [ChatMessageImageAttachment]
    var author: ChatUser
    @Binding var isShown: Bool
    /// The receiver's one view of a photo that disappears after viewing: no Share (it could be saved),
    /// no Reply (the message is gone when the viewer closes) and no grid. The sender's own photos keep
    /// all three: in a dm or a group every photo is on that lifecycle.
    var isOneTimeView: Bool
    /// Reply under a photo. The chat row sets it; nil on the group's media page, where there is no
    /// message to answer.
    var onReply: (() -> Void)?
    @State private var selected: Int
    @State private var loadedImages = [Int: UIImage]()
    @State private var gridShown: Bool
    /// The grid was opened from the chat ("8 Photos"): its back arrow closes the viewer.
    @State private var gridBackCloses: Bool

    public init(
        imageAttachments: [ChatMessageImageAttachment],
        author: ChatUser,
        isShown: Binding<Bool>,
        selected: Int
    ) {
        self.init(
            imageAttachments: imageAttachments,
            author: author,
            isShown: isShown,
            selected: selected,
            startsInGrid: false,
            isOneTimeView: false,
            onReply: nil
        )
    }

    init(
        imageAttachments: [ChatMessageImageAttachment],
        author: ChatUser,
        isShown: Binding<Bool>,
        selected: Int,
        startsInGrid: Bool,
        isOneTimeView: Bool,
        onReply: (() -> Void)?
    ) {
        self.imageAttachments = imageAttachments
        self.author = author
        _isShown = isShown
        self.isOneTimeView = isOneTimeView
        self.onReply = onReply
        _selected = State(initialValue: selected)
        _gridShown = State(initialValue: startsInGrid && !isOneTimeView)
        _gridBackCloses = State(initialValue: startsInGrid)
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if gridShown {
                GridPhotosView(
                    imageAttachments: imageAttachments,
                    onBack: {
                        if gridBackCloses {
                            isShown = false
                        } else {
                            gridShown = false
                        }
                    },
                    onSelect: { index in
                        selected = index
                        gridBackCloses = false
                        gridShown = false
                    },
                    onReply: onReply
                )
                .transition(.opacity)
            } else {
                viewer
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: gridShown)
        .preferredColorScheme(.dark)
    }

    private var viewer: some View {
        GeometryReader { reader in
            VStack(spacing: 0) {
                topBar

                // The pager is never moved or scaled as a whole (law 2026-11-20): the pull down is a
                // gesture only.
                TabView(selection: $selected) {
                    ForEach(0..<sources.count, id: \.self) { index in
                        let url = sources[index]
                        ZoomableScrollView {
                            VStack {
                                Spacer()
                                LazyGiphyView(source: url, width: reader.size.width)
                                  .aspectRatio(contentMode: .fit)
                                  .frame(width: reader.size.width)
                                Spacer()
                            }
                            .background (
                              LazyLoadingImage(
                                  source: url,
                                  width: reader.size.width,
                                  height: reader.size.height,
                                  resize: true,
                                  shouldSetFrame: false,
                                  onImageLoaded: { image in
                                      loadedImages[index] = image
                                  }
                              )
                              .aspectRatio(contentMode: .fit)
                              .frame(width: reader.size.width)
                              .opacity(0.015)
                            )
                            // Black like the rest of the viewer: the zoom view under the page paints
                            // the chat's own background.
                            .background(Color.black)
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .background(Color.black)
                .gesture(
                    DragGesture().onEnded { value in
                        if value.location.y - value.startLocation.y > 100 {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                )

                bottomBar
            }
        }
    }

    private var topBar: some View {
        ZStack {
            if sources.count > 1 {
                Text("\(selected + 1) of \(sources.count)")
                    .font(fonts.bodyBold)
                    .foregroundColor(.white)
                    .accessibilityIdentifier("GalleryCount")
            }

            HStack(spacing: 20) {
                Spacer()

                if showsGridButton {
                    Button {
                        gridBackCloses = false
                        gridShown = true
                    } label: {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 20, weight: .regular))
                            .frame(width: 32, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("GalleryGridButton")
                }

                Button {
                    isShown = false
                } label: {
                    Text("Done")
                        .font(fonts.bodyBold)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("GalleryDoneButton")
            }
            .foregroundColor(colors.tintColor)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private var bottomBar: some View {
        HStack {
            if !isOneTimeView {
                ShareButtonView(content: sharingContent, tint: colors.tintColor)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            if !isOneTimeView, let onReply {
                Button(action: onReply) {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.system(size: 21, weight: .regular))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("GalleryReplyButton")
            }
        }
        .foregroundColor(colors.tintColor)
        .padding(.horizontal, 12)
        .frame(height: 52)
    }

    private var showsGridButton: Bool {
        !isOneTimeView && sources.count > 1
    }

    private var sharingContent: [UIImage] {
        if let image = loadedImages[selected] {
            return [image]
        } else {
            return []
        }
    }

    private var sources: [URL] {
        imageAttachments.map { attachment in
            attachment.imageURL
        }
    }
}

private struct PhotoViewerReplyKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Poppin: what Reply in the photo viewer does for the row above. Nil where a reply cannot start
    /// (inside the reply view, quotes off, a deleted message), so the button is not drawn there.
    var photoViewerReply: (() -> Void)? {
        get { self[PhotoViewerReplyKey.self] }
        set { self[PhotoViewerReplyKey.self] = newValue }
    }
}
