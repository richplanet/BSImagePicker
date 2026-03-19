// The MIT License (MIT)
//
// Copyright (c) 2019 Joakim Gyllström
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import UIKit
import Photos

// MARK: ImagePickerController
@objc(BSImagePickerController)
@objcMembers open class ImagePickerController: UINavigationController {
    // MARK: Public properties
    public weak var imagePickerDelegate: ImagePickerControllerDelegate?
    public var settings: Settings = Settings()
    public var doneButton: UIBarButtonItem = UIBarButtonItem(title: "", style: .done, target: nil, action: nil)
    public var cancelButton: UIBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: nil, action: nil)
    public var albumButton: UIButton = UIButton(type: .custom)
    public var selectedAssets: [PHAsset] {
        return assetStore.assets
    }

    public var doneButtonTitle = Bundle(for: UIBarButtonItem.self)
        .localizedString(forKey: "Done", value: "Done", table: "")

    // MARK: Internal properties
    var assetStore: AssetStore
    var onSelection: ((_ asset: PHAsset) -> Void)?
    var onDeselection: ((_ asset: PHAsset) -> Void)?
    var onCancel: ((_ assets: [PHAsset]) -> Void)?
    var onFinish: ((_ assets: [PHAsset]) -> Void)?
    var onReachSelectionLimit: ((_ count: Int) -> Void)?

    let assetsViewController: AssetsViewController
    let albumsViewController = AlbumsViewController()
    let dropdownTransitionDelegate = DropdownTransitionDelegate()
    let zoomTransitionDelegate = ZoomTransitionDelegate()

    var albums: [PHAssetCollection] = []

    // MARK: Init
    public init(selectedAssets: [PHAsset] = []) {
        assetStore = AssetStore(assets: selectedAssets)
        assetsViewController = AssetsViewController(store: assetStore)
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Lifecycle
    public override func viewDidLoad() {
        super.viewDidLoad()

        albumsViewController.settings = settings
        assetsViewController.settings = settings

        albumsViewController.delegate = self
        assetsViewController.delegate = self

        viewControllers = [assetsViewController]
        view.backgroundColor = settings.theme.backgroundColor

        delegate = zoomTransitionDelegate
        presentationController?.delegate = self

        navigationBar.isTranslucent = false
        navigationBar.isOpaque = true

        setupUI()

        loadAlbums()
    }

    // MARK: UI Setup
    private func setupUI() {
        let firstViewController = viewControllers.first

        albumButton.setTitleColor(albumButton.tintColor, for: .normal)
        albumButton.titleLabel?.font = .systemFont(ofSize: 16)
        albumButton.titleLabel?.adjustsFontSizeToFitWidth = true

        let arrowView = ArrowView(frame: CGRect(x: 0, y: 0, width: 8, height: 8))
        arrowView.backgroundColor = .clear
        arrowView.strokeColor = albumButton.tintColor
        let image = arrowView.asImage

        albumButton.setImage(image, for: .normal)
        albumButton.semanticContentAttribute = .forceRightToLeft
        albumButton.addTarget(self, action: #selector(albumsButtonPressed(_:)), for: .touchUpInside)

        firstViewController?.navigationItem.titleView = albumButton

        doneButton.target = self
        doneButton.action = #selector(doneButtonPressed(_:))
        firstViewController?.navigationItem.rightBarButtonItem = doneButton

        cancelButton.target = self
        cancelButton.action = #selector(cancelButtonPressed(_:))
        firstViewController?.navigationItem.leftBarButtonItem = cancelButton

        updatedDoneButton()
        updateAlbumButton()

        if navigationBar.barTintColor == nil {
            navigationBar.barTintColor = .systemBackgroundColor
        }
    }

    // MARK: Albums 비동기 로딩
    private func loadAlbums() {
        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = self.settings.fetch.assets.options.copy() as! PHFetchOptions
            fetchOptions.fetchLimit = 1

            let fetchResults = self.settings.fetch.album.fetchResults
            var result: [PHAssetCollection] = []

            for fetchResult in fetchResults {
                for i in 0..<fetchResult.count {
                    let collection = fetchResult.object(at: i)

                    // 빠른 필터
                    if collection.estimatedAssetCount == 0 {
                        continue
                    }

                    // 🔥 IPC (백그라운드에서 실행)
                    let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)

                    if assets.count > 0 {
                        result.append(collection)
                    }
                }
            }

            DispatchQueue.main.async {
                self.albums = result
                self.updateAlbumButton()

                if let firstAlbum = result.first {
                    self.select(album: firstAlbum)
                }
            }
        }
    }

    // MARK: Actions
    public func deselect(asset: PHAsset) {
        assetStore.remove(asset)
        assetsViewController.unselect(asset: asset)
        updatedDoneButton()
    }

    func updatedDoneButton() {
        doneButton.title = assetStore.count > 0 ? doneButtonTitle + " (\(assetStore.count))" : doneButtonTitle
        doneButton.isEnabled = assetStore.count >= settings.selection.min
    }

    func updateAlbumButton() {
        albumButton.isHidden = albums.count < 2
    }
}
