//
// Copyright © 2024 Stream.io Inc. All rights reserved.
//

import StreamChat
import SwiftUI

/// View used for displaying photos in a grid.
///
/// Poppin (2026-11-21): the photo viewer's second face, like the grid in Messages. Two columns, each
/// photo whole in its own shape with round corners, a back arrow, Reply. A tap opens that photo.
struct GridPhotosView: View {
    @Injected(\.colors) private var colors

    var imageAttachments: [ChatMessageImageAttachment]
    var onBack: () -> Void
    var onSelect: (Int) -> Void
    var onReply: (() -> Void)?

    private static let gap: CGFloat = 24
    private static let cornerRadius: CGFloat = 14

    private let columns = [
        GridItem(.flexible(), spacing: GridPhotosView.gap),
        GridItem(.flexible(), spacing: GridPhotosView.gap)
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 21, weight: .semibold))
                        .frame(width: 44, height: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("GridBackButton")
                Spacer()
            }
            .padding(.horizontal, 16)

            // popup-fit: fills, a scrolling grid of photos
            GeometryReader { reader in
                let cell = max(60, ((reader.size.width - Self.gap * 3) / 2).rounded(.down))
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Self.gap) {
                        ForEach(imageAttachments.indices, id: \.self) { index in
                            tile(index, cell: cell)
                        }
                    }
                    .padding(.horizontal, Self.gap)
                    .padding(.vertical, 12)
                }
            }

            if let onReply {
                HStack {
                    Button(action: onReply) {
                        Image(systemName: "arrowshape.turn.up.left")
                            .font(.system(size: 21, weight: .regular))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("GridReplyButton")
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 52)
            }
        }
        .foregroundColor(colors.tintColor)
        .background(Color(red: 0.11, green: 0.11, blue: 0.118).ignoresSafeArea())
        .accessibilityIdentifier("GridPhotosView")
    }

    private func tile(_ index: Int, cell: CGFloat) -> some View {
        let attachment = imageAttachments[index]
        let box = CGSize(width: cell, height: (cell * 1.3).rounded())
        // A photo with no size on the wire fills a square.
        let size = PhotoShape.size(ratio: PhotoShape.ratio(of: attachment) ?? 1, in: box)
        return LazyLoadingImage(
            source: attachment.imageURL,
            width: size.width,
            height: size.height
        )
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .frame(width: box.width, height: box.height)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect(index)
        }
        .accessibilityIdentifier("GridPhotoTile")
    }
}
