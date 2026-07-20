import SwiftUI

struct RootView: View {
    var body: some View {
        #if os(macOS)
        MacLibraryRootView()
        #else
        MobileAppShellView()
        #endif
    }
}
