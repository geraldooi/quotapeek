import AppKit
import QuotaPeekCore
import SwiftUI

struct ProviderLogo: View {
    let provider: Provider
    var size: CGFloat = 28

    var body: some View {
        if let image = logoImage {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }

    private var logoImage: NSImage? {
        let resourceName = provider == .codex ? "codex" : "claude-code"
        guard let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: "png",
            subdirectory: "BrandIcons"
        ) ?? Bundle.module.url(
            forResource: resourceName,
            withExtension: "png",
            subdirectory: "BrandIcons"
        ) ?? Bundle.module.url(forResource: resourceName, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
