//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

// `group` function lifted from https://stackoverflow.com/a/31220067
fileprivate class Box<A> {
    var value: A
    init(_ val: A) {
        self.value = val
    }
}

public extension Sequence {
    func group<U: Hashable>(by key: (Iterator.Element) -> U) -> [U:[Iterator.Element]] {
        var categories: [U: Box<[Iterator.Element]>] = [:]
        for element in self {
            let key = key(element)
            if case nil = categories[key]?.value.append(element) {
                categories[key] = Box([element])
            }
        }
        var result: [U: [Iterator.Element]] = Dictionary(minimumCapacity: categories.count)
        for (key, val) in categories {
            result[key] = val.value
        }
        return result
    }
}

class AllMediaViewController: UICollectionViewController {

    private struct MediaGalleryItem: Equatable {
        let message: TSMessage
        let attachmentStream: TSAttachmentStream

        var isVideo: Bool {
            return attachmentStream.isVideo()
        }

        var image: UIImage {
            guard let image = attachmentStream.image() else {
                owsFail("\(logTag) in \(#function) unexpectedly unagble to build attachment image")
                return UIImage()
            }

            return image
        }
    }

    private struct GalleryDate: Hashable {
        let year: Int
        let month: Int

        init(message: TSMessage) {
            let date = message.dateForSorting()

            self.year = Calendar.current.component(.year, from: date)
            self.month = Calendar.current.component(.month, from: date)
        }

        init(year: Int, month: Int) {
            self.year = year
            self.month = month
        }

        private var isThisMonth: Bool {
            let now = Date()
            let year = Calendar.current.component(.year, from: now)
            let month = Calendar.current.component(.month, from: now)
            let thisMonth = GalleryDate(year: year, month: month)

            return self == thisMonth
        }

        public var date: Date {
            var components = DateComponents()
            components.month = self.month
            components.year = self.year

            return Calendar.current.date(from: components)!
        }

        private var isThisYear: Bool {
            let now = Date()
            let thisYear = Calendar.current.component(.year, from: now)

            return self.year == thisYear
        }

        static let thisYearFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM"

            return formatter
        }()

        static let olderFormatter: DateFormatter = {
            let formatter = DateFormatter()

            // FIXME localize for RTL, or is there a built in way to do this?
            formatter.dateFormat = "MMMM yyyy"

            return formatter
        }()

        // FIXME
        var localizedString: String {
            if isThisMonth {
                return NSLocalizedString("MEDIA_GALLERY_THIS_MONTH_HEADER", comment: "Section header in media gallery collection view")
            } else if isThisYear {
                return type(of: self).thisYearFormatter.string(from: self.date)
            } else {
                return type(of: self).olderFormatter.string(from: self.date)
            }
        }
    }

    private var sections: [GalleryDate: [MediaGalleryItem]] = [:]
    private var sectionDates: [GalleryDate] = []
    private let uiDatabaseConnection: YapDatabaseConnection

    let kSectionHeaderReuseIdentifier = "kSectionHeaderReuseIdentifier"
    let kCellReuseIdentifier = "kCellReuseIdentifier"

    init(mediaMessages: [TSMessage], uiDatabaseConnection: YapDatabaseConnection) {

        let screenWidth = UIScreen.main.bounds.size.width
        let kItemsPerRow = 4
        let kInterItemSpacing: CGFloat = 2

        let availableWidth = screenWidth - CGFloat(kItemsPerRow + 1) * kInterItemSpacing
        let kItemWidth = floor(availableWidth / CGFloat(kItemsPerRow))

        let layout: UICollectionViewFlowLayout = UICollectionViewFlowLayout()
        layout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        layout.itemSize = CGSize(width: kItemWidth, height: kItemWidth)
        layout.minimumInteritemSpacing = kInterItemSpacing
        layout.minimumLineSpacing = kInterItemSpacing
        layout.sectionHeadersPinToVisibleBounds = true

        let kHeaderHeight: CGFloat = 50
        layout.headerReferenceSize = CGSize(width: 0, height: kHeaderHeight)

        self.uiDatabaseConnection = uiDatabaseConnection

        super.init(collectionViewLayout: layout)

        updateSections(mediaMessages: mediaMessages)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: View Lifecycle Overrides

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = MediaStrings.allMedia

        guard let collectionView = self.collectionView else {
            owsFail("\(logTag) in \(#function) collectionView was unexpectedly nil")
            return
        }
        collectionView.backgroundColor = UIColor.white
        collectionView.register(MediaGalleryCell.self, forCellWithReuseIdentifier: kCellReuseIdentifier)
        collectionView.register(MediaGallerySectionHeader.self, forSupplementaryViewOfKind: UICollectionElementKindSectionHeader, withReuseIdentifier: kSectionHeaderReuseIdentifier)

        // FIXME: For some reason this is scrolling not *quite* to the bottom in viewDidLoad.
        // It does work in viewDidAppear. What changes?
        self.view.layoutIfNeeded()
        scrollToBottom(animated: false)
    }

    // MARK: UIColletionViewDataSource

    override public func numberOfSections(in collectionView: UICollectionView) -> Int {
        return sections.keys.count
    }

    override public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection sectionIdx: Int) -> Int {
        guard let sectionDate = self.sectionDates[safe: sectionIdx] else {
            owsFail("\(logTag) in \(#function) unknown section: \(sectionIdx)")
            return 0
        }

        guard let section = self.sections[sectionDate] else {
            owsFail("\(logTag) in \(#function) no section for date: \(sectionDate)")
            return 0
        }

        // We shouldn't show empty sections
        assert(section.count > 0)

        return section.count
    }

    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {

        let defaultView = UICollectionReusableView()
        if (kind == UICollectionElementKindSectionHeader) {
            guard let sectionHeader = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kSectionHeaderReuseIdentifier, for: indexPath) as? MediaGallerySectionHeader else {
                owsFail("\(logTag) in \(#function) unable to build section header for indexPath: \(indexPath)")
                return defaultView
            }
            guard let date = self.sectionDates[safe: indexPath.section] else {
                owsFail("\(logTag) in \(#function) unknown section for indexPath: \(indexPath)")
                return defaultView
            }

            sectionHeader.configure(title: date.localizedString)
            return sectionHeader
        }

        return defaultView
    }

    override public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

        let defaultCell = UICollectionViewCell()

        guard let sectionDate = self.sectionDates[safe: indexPath.section] else {
            owsFail("\(logTag) in \(#function) unknown section: \(indexPath.section)")
            return defaultCell
        }

        guard let section = self.sections[sectionDate] else {
            owsFail("\(logTag) in \(#function) no section for date: \(sectionDate)")
            return defaultCell
        }

        guard let galleryItem = section[safe: indexPath.row] else {
            owsFail("\(logTag) in \(#function) no message for row: \(indexPath.row)")
            return defaultCell
        }

        guard let cell = self.collectionView?.dequeueReusableCell(withReuseIdentifier: kCellReuseIdentifier, for: indexPath) as? MediaGalleryCell else {
            owsFail("\(logTag) in \(#function) unexptected cell for indexPath: \(indexPath)")
            return defaultCell
        }

        cell.configure(image: galleryItem.image)

        return cell
    }

    // MARK: Util

    private func scrollToBottom(animated isAnimated: Bool) {
        guard let collectionView = self.collectionView else {
            owsFail("\(self.logTag) in \(#function) collectionView was unexpectedly nil")
            return
        }

        let yOffset: CGFloat = collectionView.contentSize.height - collectionView.bounds.size.height + collectionView.contentInset.bottom
        let offset: CGPoint  = CGPoint(x: 0, y: yOffset)

        collectionView.setContentOffset(offset, animated: isAnimated)
    }

    private func updateSections(mediaMessages: [TSMessage]) {
        var sections: [GalleryDate: [MediaGalleryItem]] = [:]
        var sectionDates: [GalleryDate] = []

        self.uiDatabaseConnection.read { transaction in
            for message in mediaMessages {
                guard let attachmentStream = message.attachment(with: transaction) as? TSAttachmentStream else {
                    owsFail("\(self.logTag) in \(#function) attachment was unexpectedly empty")
                    continue
                }

                let item = MediaGalleryItem(message: message, attachmentStream: attachmentStream)
                let date = GalleryDate(message: message)

                if sections[date] != nil {
                    sections[date]!.append(item)
                } else {
                    sectionDates.append(date)
                    sections[date] = [item]
                }
            }
        }

        self.sections = sections
        self.sectionDates = sectionDates

        self.collectionView?.reloadData()
    }

}

class MediaGallerySectionHeader: UICollectionReusableView {

    let label: UILabel

    override init(frame: CGRect) {
        label = UILabel()

        let blurEffect = UIBlurEffect(style: .light)
        let blurEffectView = UIVisualEffectView(effect: blurEffect)

        blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        super.init(frame: frame)

        self.addSubview(blurEffectView)
        self.addSubview(label)

        blurEffectView.autoPinEdgesToSuperviewEdges()
        label.autoPinEdge(toSuperviewEdge: .trailing)
        label.autoPinEdge(toSuperviewEdge: .leading, withInset: 10)
        label.autoVCenterInSuperview()
    }

    @available(*, unavailable, message: "Unimplemented")
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(title: String) {
        self.label.text = title
    }

    override public func prepareForReuse() {
        super.prepareForReuse()

        self.label.text = nil
    }
}

class MediaGalleryCell: UICollectionViewCell {

    private let imageView: UIImageView

    override init(frame: CGRect) {
        self.imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill

        super.init(frame: frame)

        self.clipsToBounds = true
        self.addSubview(imageView)

        imageView.autoPinEdgesToSuperviewEdges()
    }

    @available(*, unavailable, message: "Unimplemented")
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(image: UIImage) {
        self.imageView.image = image
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        self.imageView.image = nil
    }
}
