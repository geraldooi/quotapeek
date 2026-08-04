---
status: accepted
---

# Use native dependency-free Swift

QuotaPeek is a native macOS Swift Package with a dependency-free
`QuotaPeekCore` target for models and parsing and a `QuotaPeek` executable target
for SwiftUI and AppKit presentation. System frameworks keep the menu-bar app
small, auditable, and straightforward to package for macOS 13 or newer; AppKit
is used only where SwiftUI does not provide reliable menu-bar behavior. A new
package dependency requires an explicit decision because it expands the build,
security, licensing, and release surface.
