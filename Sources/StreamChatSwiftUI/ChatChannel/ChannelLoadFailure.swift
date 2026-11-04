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
    /// The server says the channel is gone (HTTP 404, never an auth rejection riding a 404): a
    /// row cached before the sync delta that removes it landed, most often a deleted account's
    /// DM (Jackie 11-03: a deleted account leaves no tell anywhere in the app), or a DM create
    /// refused for a gone or banned peer. The engine retires a cached row on the channel's own
    /// 403/404 (`forgetChannel`, `ChatChannelController+Store`), then `ChatChannelViewModel`
    /// offers `.retired` on the `.remove` change. Carries the rejection: a DM create's 404 has
    /// the backend's neutral copy ("This chat isn't available") for the app to toast; a GET 404
    /// and a retired row carry none, so the app pops in silence and nothing says why.
    case gone(ChatRejection)
    /// Anything else: membership, decode, transport, unknown.
    case generic

    /// The engine retired the channel under an open screen (`EntityChange.remove`): no wire
    /// rejection to carry, so a bare 404 with no copy, which keeps the app's handler silent.
    public static var retired: ChannelLoadFailure {
        .gone(ChatRejection(kind: .server, status: 404))
    }

    public static func classify(_ error: Error) -> ChannelLoadFailure {
        guard let rejection = error.chatRejection else { return .generic }
        if rejection.isOffline { return .offline }
        if rejection.isRateLimited { return .cooldown(rejection) }
        if rejection.isServerBusy { return .busy }
        if rejection.kind == .server, rejection.status == 404, !rejection.isAuthRejected {
            return .gone(rejection)
        }
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
        case let .gone(rejection):
            // Only when the app's handler did not pop: the backend's copy when it sent one, else
            // its DM-create 404 wording, no reason given.
            return rejection.display.isEmpty ? "This chat isn't available" : rejection.display
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
        case let .gone(rejection):
            return rejection.subDisplay.isEmpty ? nil : rejection.subDisplay
        case .generic:
            return nil
        }
    }
}
