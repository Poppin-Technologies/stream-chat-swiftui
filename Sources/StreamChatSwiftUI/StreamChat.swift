//
// Copyright © 2024 Stream.io Inc. All rights reserved.
//

import StreamChat

/// Main interface to the SwiftUI SDK.
///
/// Provides context for the views and view models. Must be initialized with a `ChatClient` on app start.
public class StreamChat {
    public var chatClient: ChatClient
    public var appearance: Appearance
    public var utils: Utils

    public init(
        chatClient: ChatClient,
        appearance: Appearance = Appearance(),
        utils: Utils = Utils()
    ) {
        self.chatClient = chatClient
        self.appearance = appearance
        self.utils = utils
        StreamChatProviderKey.currentValue = self
    }
}

/// Returns the current value for the `StreamChat` instance.
private struct StreamChatProviderKey: InjectionKey {
    static var currentValue: StreamChat?
}

extension InjectedValues {
    /// Provides access to the `StreamChat` instance in the views and view models.
    public var streamChat: StreamChat {
        get {
            guard let injected = Self[StreamChatProviderKey.self] else {
                fatalError("Chat client was not setup")
            }
            return injected
        }
        set {
            Self[StreamChatProviderKey.self] = newValue
        }
    }
}

struct Constants {
  static let photoPickerDropDown = "photo_picker_drop_down"
}
