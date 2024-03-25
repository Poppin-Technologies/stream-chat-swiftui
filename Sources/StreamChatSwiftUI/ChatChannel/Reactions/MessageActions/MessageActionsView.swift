//
// Copyright © 2024 Stream.io Inc. All rights reserved.
//

import SwiftUI

/// View for the message actions.
@available(iOS 15.0, *)
public struct MessageActionsView: View {
    @Injected(\.colors) private var colors

    @State var presenting: Bool = false
    @StateObject var viewModel: MessageActionsViewModel

    public init(messageActions: [MessageAction]) {
        _viewModel = StateObject(
            wrappedValue: ViewModelsFactory
                .makeMessageActionsViewModel(messageActions: messageActions)
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.messageActions) { action in
                VStack(spacing: 0) {
                    if let destination = action.navigationDestination {
                        Button {
                          presenting = true
                        } label: {
                            ActionItemView(
                                title: action.title,
                                iconName: action.iconName,
                                isDestructive: action.isDestructive,
                                boldTitle: false
                            )
                        }
                        .background {
                          NavigationLink("", isActive: $presenting) {
                              destination
                          }
                        }
                    } else {
                        Button {
                            if action.confirmationPopup != nil {
                                viewModel.alertAction = action
                            } else {
                                action.action()
                            }
                        } label: {
                            ActionItemView(
                                title: action.title,
                                iconName: action.iconName,
                                isDestructive: action.isDestructive,
                                boldTitle: false
                            )
                        }
                    }

                    Divider()
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("messageAction-\(action.id)")
            }
        }
        .background(Material.ultraThickMaterial)
        .roundWithBorder(cornerRadius: 12)
        .alert(isPresented: $viewModel.alertShown) {
            let title = viewModel.alertAction?.confirmationPopup?.title ?? ""
            let message = viewModel.alertAction?.confirmationPopup?.message ?? ""
            let buttonTitle = viewModel.alertAction?.confirmationPopup?.buttonTitle ?? ""

            return Alert(
                title: Text(title),
                message: Text(message),
                primaryButton: .destructive(Text(buttonTitle)) {
                    viewModel.alertAction?.action()
                },
                secondaryButton: .cancel()
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("MessageActionsView")
    }
}
