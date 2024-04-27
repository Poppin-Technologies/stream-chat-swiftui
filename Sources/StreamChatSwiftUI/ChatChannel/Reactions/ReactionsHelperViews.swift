//
// Copyright © 2024 Stream.io Inc. All rights reserved.
//

import StreamChat
import SwiftUI

public struct ReactionsHStack<Content: View>: View {
    @Injected(\.utils) var utils
    var message: ChatMessage
    var content: () -> Content

    public init(message: ChatMessage, content: @escaping () -> Content) {
        self.message = message
        self.content = content
    }

    public var body: some View {
        HStack {
            if !utils.isSentByCurrentUser(message)  {
                Spacer()
            }

            content()

            if utils.isSentByCurrentUser(message) {
                Spacer()
            }
        }
    }
}
