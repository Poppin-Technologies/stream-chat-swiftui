//
// Copyright © 2024 Stream.io Inc. All rights reserved.
//

import Photos
import StreamChat
import SwiftUI

/// View for the attachment picker.
public struct AttachmentPickerView<Factory: ViewFactory>: View {

  @EnvironmentObject var viewmodel: MessageComposerViewModel
    @Injected(\.colors) private var colors
    @Injected(\.fonts) private var fonts

    var viewFactory: Factory
    @Binding var selectedPickerState: AttachmentPickerState
    @Binding var filePickerShown: Bool
    @Binding var cameraPickerShown: Bool
    @Binding var addedFileURLs: [URL]
    var onPickerStateChange: (AttachmentPickerState) -> Void
    var photoLibraryAssets: PHFetchResult<PHAsset>?
    var onAssetTap: (AddedAsset) -> Void
    var onCustomAttachmentTap: (CustomAttachment) -> Void
    var isAssetSelected: (String) -> Bool
    var addedCustomAttachments: [CustomAttachment]
    var cameraImageAdded: (AddedAsset) -> Void
    var askForAssetsAccessPermissions: () -> Void

    var isDisplayed: Bool
    var height: CGFloat
  
    @State var displayingImagePicker: Bool = false

    public init(
        viewFactory: Factory,
        selectedPickerState: Binding<AttachmentPickerState>,
        filePickerShown: Binding<Bool>,
        cameraPickerShown: Binding<Bool>,
        addedFileURLs: Binding<[URL]>,
        onPickerStateChange: @escaping (AttachmentPickerState) -> Void,
        photoLibraryAssets: PHFetchResult<PHAsset>? = nil,
        onAssetTap: @escaping (AddedAsset) -> Void,
        onCustomAttachmentTap: @escaping (CustomAttachment) -> Void,
        isAssetSelected: @escaping (String) -> Bool,
        addedCustomAttachments: [CustomAttachment],
        cameraImageAdded: @escaping (AddedAsset) -> Void,
        askForAssetsAccessPermissions: @escaping () -> Void,
        isDisplayed: Bool,
        height: CGFloat
    ) {
        self.viewFactory = viewFactory
        _selectedPickerState = selectedPickerState
        _filePickerShown = filePickerShown
        _cameraPickerShown = cameraPickerShown
        _addedFileURLs = addedFileURLs
        self.onPickerStateChange = onPickerStateChange
        self.photoLibraryAssets = photoLibraryAssets
        self.onAssetTap = onAssetTap
        self.onCustomAttachmentTap = onCustomAttachmentTap
        self.isAssetSelected = isAssetSelected
        self.addedCustomAttachments = addedCustomAttachments
        self.cameraImageAdded = cameraImageAdded
        self.askForAssetsAccessPermissions = askForAssetsAccessPermissions
        self.isDisplayed = isDisplayed
        self.height = height
    }
  
  @State private var barOffset: CGFloat = .zero

  public var body: some View {
    VStack(spacing: 0) {
      HStack {
        Spacer()
        Rectangle()
          .frame(height: 6)
          .frame(width: 60)
          .background(barOffset < -75 ? Color.pink : Color.white)
          .opacity(abs(barOffset) > 75 ? 1.0 : 0.2)
          .opacity(0.7)
          .cornerRadius(16)
          .padding(.vertical, 7)
        Spacer()
      }
      .padding(.top, 6)
      .padding(.bottom, 6)
      .background(Color.init(red: 0.07, green: 0.07, blue: 0.07))
      .animation(.easeInOut(duration: 0.1), value: barOffset)
      .gesture(DragGesture().onChanged({ gesture in
        if abs(barOffset) <= 75, abs(gesture.translation.height) > 75 {
          UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        barOffset = gesture.translation.height
      }).onEnded({ gesture in
        if (gesture.translation.height) > 75 {
          withAnimation(.interpolatingSpring(stiffness: 170, damping: 25)) {
            viewmodel.pickerTypeState = .expanded(.none)
          }
        }
        if (gesture.translation.height) < -75 {
          displayingImagePicker = true
        }
        barOffset = 0
      }))
      .sheet(isPresented: $displayingImagePicker) {
        ImagePickerView(sourceType: .photoLibrary, onAssetPicked: onAssetTap)
          .ignoresSafeArea(.all)
      }
      if let assets = photoLibraryAssets {
        let collection = PHFetchResultCollection(fetchResult: assets)
        if !collection.isEmpty {
          viewFactory.makePhotoAttachmentPickerView(
            assets: collection,
            onAssetTap: onAssetTap,
            isAssetSelected: isAssetSelected
          )
          .edgesIgnoringSafeArea(.bottom)
        } else {
          viewFactory.makeAssetsAccessPermissionView()
        }
      } else {
        LoadingView()
      }
    }
    .frame(height: height - 0.1 * barOffset)
    .background(Color(colors.background1))
    .onChange(of: isDisplayed) { newValue in
      if newValue {
        askForAssetsAccessPermissions()
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("AttachmentPickerView")
  }
}

/// View for picking the source of the attachment (photo, files or camera).
public struct AttachmentSourcePickerView: View {

    @Injected(\.colors) private var colors
    @Injected(\.images) private var images

    var selected: AttachmentPickerState
    var onTap: (AttachmentPickerState) -> Void

    public init(
        selected: AttachmentPickerState,
        onTap: @escaping (AttachmentPickerState) -> Void
    ) {
        self.selected = selected
        self.onTap = onTap
    }

    public var body: some View {

        HStack(alignment: .center, spacing: 24) {
            AttachmentPickerButton(
                icon: images.attachmentPickerPhotos,
                pickerType: .photos,
                isSelected: selected == .photos,
                onTap: onTap
            )
            .accessibilityIdentifier("attachmentPickerPhotos")

            AttachmentPickerButton(
                icon: images.attachmentPickerFolder,
                pickerType: .files,
                isSelected: selected == .files,
                onTap: onTap
            )
            .accessibilityIdentifier("attachmentPickerFiles")

            AttachmentPickerButton(
                icon: images.attachmentPickerCamera,
                pickerType: .camera,
                isSelected: selected == .camera,
                onTap: onTap
            )
            .accessibilityIdentifier("attachmentPickerCamera")

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Color(colors.background1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("AttachmentSourcePickerView")
    }
}

/// Button used for picking of attachment types.
public struct AttachmentPickerButton: View {
    @Injected(\.colors) private var colors

    var icon: UIImage
    var pickerType: AttachmentPickerState
    var isSelected: Bool
    var onTap: (AttachmentPickerState) -> Void

    public init(
        icon: UIImage,
        pickerType: AttachmentPickerState,
        isSelected: Bool,
        onTap: @escaping (AttachmentPickerState) -> Void
    ) {
        self.icon = icon
        self.pickerType = pickerType
        self.isSelected = isSelected
        self.onTap = onTap
    }

    public var body: some View {
        Button {
            onTap(pickerType)
        } label: {
            Image(uiImage: icon)
                .customizable()
                .frame(width: 22)
                .foregroundColor(
                    isSelected ? Color(colors.highlightedAccentBackground)
                        : Color(colors.textLowEmphasis)
                )
        }
    }
}
