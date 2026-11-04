//
// Copyright © 2024 Stream.io Inc. All rights reserved.
//

import Foundation
import StreamChat

/// Why a channel could not be loaded when there was nothing cached to show. Drives the error
/// state of `ChatChannelView` (copy per case + Retry) and the app's
/// `Utils.channelLoadFailureHandler`.
///
/// Before (2026-09-06) every failed load was one boolean and one string, so an anti-spam
/// suspension refusing a brand-new DM (HTTP 429 with the backend's own copy and cooldown) read
/// as "Couldn't load this conversation" - the same as being offline (Jackie, image 1).
public enum ChannelLoadFailure: Equatable {
    /// The server refused to open the channel because the viewer is rate-limited. Today that is
    /// only the anti-spam suspension on `POST /chat/channels` for a fresh DM (host chats and
    /// existing channels have no limiter). Carries the backend copy and the remaining cooldown.
    case cooldown(ChatRejection)
    /// No usable network on the device.
    case offline
    /// The server shed the request (503 / code 9503) - worth a retry in a moment.
    case busy
    /// The server says the channel is gone (HTTP 404): a row cached before the sync delta that
    /// removes it landed, most often a deleted account's DM (Jackie 11-03: a deleted account
    /// leaves no tell anywhere in the app). The engine has already dropped the row
    /// (`forgetChannelIfGone`); the app's handler pops with no toast, so nothing says why.
    case gone
    /// Anything else: membership, decode, transport, unknown.
    case generic

    public static func classify(_ error: Error) -> ChannelLoadFailure {
        guard let rejection = error.chatRejection else { return .generic }
        if rejection.isOffline { return .offline }
        if rejection.isRateLimited { return .cooldown(rejection) }
        if rejection.isServerBusy { return .busy }
        if rejection.kind == .server, rejection.status == 404 { return .gone }
        return .generic
    }

    /// Headline of the built-in error state.
    public var title: String {
        switch self {
        case let .cooldown(rejection):
            return rejection.display.isEmpty ? "Messaging is temporarily paused" : rejection.display
        case .offline:
            return "You're offline"
        case .busy:
            return "Poppin is busy right now"
        case .gone:
            // Only when the app's handler did not pop: the backend's own 404 copy, no reason given.
            return "This chat isn't available"
        case .generic:
            return "Couldn't load this conversation"
        }
    }

    /// Second line of the built-in error state; nil when the headline says it all.
    public var subtitle: String? {
        switch self {
        case let .cooldown(rejection):
            return rejection.subDisplay.isEmpty ? nil : rejection.subDisplay
        case .offline:
            return "Check your connection and try again."
        case .busy:
            return "Try again in a moment."
        case .gone, .generic:
            return nil
        }
    }
}
