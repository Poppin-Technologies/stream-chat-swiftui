//
// Copyright © 2024 Stream.io Inc. All rights reserved.
//

import ShinySwiftUI
import SwiftUI

/// View for the  action item in an action list (for channels and messages).
public struct ActionItemView: View {
    @Injected(\.colors) private var colors
    @Injected(\.images) private var images
    @Injected(\.fonts) private var fonts

    var title: String
    var iconName: String
    var isDestructive: Bool
    var boldTitle: Bool = true

    public var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.body)
                .if(boldTitle) {
                  $0.bold()
                }
                .foregroundColor(
                    isDestructive ? Color(colors.alert) : Color(colors.text)
                )
                .padding(.leading)

          Spacer()

          Image(uiImage: image)
              .customizable()
              .frame(width: 18, height: 18)
              .foregroundColor(
                isDestructive ? Color(colors.alert) : Color.white
              )
              .padding(.trailing)
        }
        .frame(height: 40)
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
    }

    private var image: UIImage {
        // Support for system images.
        if let image = UIImage(systemName: iconName) {
            return image
        }
      
        // Check if it's in the app bundle.
        if let image = UIImage(named: iconName) {
            return image
        }

        // Check if it's bundled.
        if let image = UIImage(named: iconName, in: .streamChatUI) {
            return image
        }

        // Default image.
        return images.photoDefault
    }
}
