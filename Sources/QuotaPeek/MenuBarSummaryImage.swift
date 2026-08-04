import AppKit
import QuotaPeekCore
import SwiftUI

struct MenuBarSummaryImage: View {
    let items: [MenuBarSummaryItem]

    var body: some View {
        if let image = renderedImage {
            Image(nsImage: image)
                .renderingMode(.original)
                .accessibilityHidden(true)
        } else {
            Text(fallbackText)
        }
    }

    private var renderedImage: NSImage? {
        let iconSize: CGFloat = 18
        let iconSpacing: CGFloat = 4
        let separator = " · "
        let font = NSFont.menuBarFont(ofSize: 0)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]

        func textWidth(_ text: String) -> CGFloat {
            ceil((text as NSString).size(withAttributes: attributes).width)
        }

        let separatorWidth = textWidth(separator)
        let fragments = items.enumerated().compactMap { index, item -> Fragment? in
            guard let image = ProviderLogoAsset.image(for: item.provider) else { return nil }
            return Fragment(
                image: image,
                value: item.value.displayText,
                leadingSeparatorWidth: index == 0 ? 0 : separatorWidth,
                valueWidth: textWidth(item.value.displayText)
            )
        }
        guard fragments.count == items.count else { return nil }

        let width = fragments.reduce(CGFloat.zero) { result, fragment in
            result
                + fragment.leadingSeparatorWidth
                + iconSize
                + iconSpacing
                + fragment.valueWidth
        }
        let textHeight = ceil(font.ascender - font.descender)
        let height = max(iconSize, textHeight)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            var x: CGFloat = 0
            let textY = floor((height - textHeight) / 2)

            for fragment in fragments {
                if fragment.leadingSeparatorWidth > 0 {
                    (separator as NSString).draw(
                        at: NSPoint(x: x, y: textY),
                        withAttributes: attributes
                    )
                    x += fragment.leadingSeparatorWidth
                }

                fragment.image.draw(
                    in: NSRect(
                        x: x,
                        y: floor((height - iconSize) / 2),
                        width: iconSize,
                        height: iconSize
                    ),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: true,
                    hints: [.interpolation: NSImageInterpolation.high]
                )
                x += iconSize + iconSpacing

                (fragment.value as NSString).draw(
                    at: NSPoint(x: x, y: textY),
                    withAttributes: attributes
                )
                x += fragment.valueWidth
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private var fallbackText: String {
        items.map { item in
            "\(item.provider.displayName) \(item.value.displayText)"
        }.joined(separator: " · ")
    }
}

private struct Fragment {
    let image: NSImage
    let value: String
    let leadingSeparatorWidth: CGFloat
    let valueWidth: CGFloat
}
