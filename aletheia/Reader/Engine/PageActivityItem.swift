//
//  PageActivityItem.swift
//  aletheia
//
//  Created by Angelo Carasig on 13/8/2026.
//

import LinkPresentation
import UIKit

// the share sheet's header is built from LPLinkMetadata and nothing else - hand
// it a bare UIImage and it falls back to the app icon and the app's name
final class PageActivityItem: NSObject, UIActivityItemSource {
    private let image: UIImage
    private let title: String
    private let subtitle: String

    init(image: UIImage, title: String, subtitle: String) {
        self.image = image
        self.title = title
        self.subtitle = subtitle
    }

    // never the real image: the placeholder is asked for synchronously on the
    // main thread to size the sheet, and a full page is megabytes of it
    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
        UIImage()
    }

    func activityViewController(
        _ controller: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        image
    }

    func activityViewController(
        _ controller: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        "\(title) - \(subtitle)"
    }

    func activityViewControllerLinkMetadata(_ controller: UIActivityViewController)
        -> LPLinkMetadata?
    {
        let metadata = LPLinkMetadata()
        metadata.title = title

        // LPLinkMetadata has no subtitle field - its second line is drawn from
        // the url's last path component, so a file url carrying only the text
        // puts that line under our control. nothing ever resolves this url
        metadata.originalURL = URL(
            fileURLWithPath: subtitle.replacingOccurrences(of: "/", with: " "))
        metadata.imageProvider = NSItemProvider(object: image)

        return metadata
    }
}
