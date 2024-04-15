//
// Copyright © 2024 Stream.io Inc. All rights reserved.
//

import StreamChat
import SwiftUI

struct RecordingView: View {
    
    @Injected(\.colors) var colors
    @Injected(\.utils) var utils
    
    var location: CGPoint
    var audioRecordingInfo: AudioRecordingInfo
    @ObservedObject var viewModel: MessageComposerViewModel
    var namespace: Namespace.ID
    var onMicTap: () -> Void
    
    private let initialLockOffset: CGFloat = -70
      
  var loc: CGPoint {
    if case let .recording(l) = viewModel.recordingState {
      return l
    }
    return .zero
  }
  
    var body: some View {
        HStack {
            Image(systemName: "mic")
                .foregroundColor(.red)
            RecordingDurationView(duration: audioRecordingInfo.duration)
              .opacity(viewModel.recordingState == .initial ? 0 : 1)
              .animation(.easeIn, value: viewModel.recordingState)
              .matchedGeometryEffect(id: "RecordingView", in: namespace)
          
            Spacer()
            
            HStack {
                Text(L10n.Composer.Recording.slideToCancel)
                Image(systemName: "chevron.left")
            }
            .foregroundColor(Color(colors.textLowEmphasis))
            .opacity(opacityForSlideToCancel)
            .transition(.opacity.animation(.easeInOut))
            
            Spacer()
            
            Button {
                onMicTap()
            } label: {
                Image(systemName: "mic")
                .font(.body.weight(.semibold))
                .foregroundColor(colors.tintColor)

            }
        }
        .padding(.all, 12)
        .overlay(
            TopRightView {
                LockView()
                    .padding(.all, 4)
                    .offset(y: lockViewOffset)
            }
        )
    }
    
    private var lockViewOffset: CGFloat {
        if loc.y > 0 {
            return initialLockOffset
        }
        return initialLockOffset + loc.y
    }
    
    private var opacityForSlideToCancel: CGFloat {
        guard loc.x < RecordingConstants.cancelMinDistance else { return 1 }
        let opacity = (1 - loc.x / RecordingConstants.cancelMaxDistance)
        return opacity
    }
}

struct LockView: View {
    @Injected(\.colors) var colors
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock")
            Image(systemName: "chevron.up")
        }
        .padding(.all, 8)
        .padding(.vertical, 2)
        .foregroundColor(Color(colors.textLowEmphasis))
        .background(Color(colors.background6))
        .cornerRadius(16)
    }
}
