# Known issues

## Xcode 27 beta 3 binary does not launch on the installed iOS 17 runtime

Observed with Xcode 27 beta 3 (`27A5218g`) and the installed iOS 17.0 Simulator runtime.

The app builds successfully for an iOS 17 deployment target, but dyld terminates it before `main` because the iOS 17 SwiftUI framework does not contain this symbol emitted by the beta toolchain:

```text
SwiftUI.LazyState.wrappedValue.init
```

This is a toolchain/runtime compatibility issue, not an application crash. Do not add private-symbol workarounds. Validate the iPhone UI with an iOS 27 runtime when using Xcode 27 beta 3, and retain the iOS 17 deployment target until it can be regression-tested with a fixed Xcode 27 build or a complete stable Xcode 26 platform installation.

### Verified compatible configuration

Verified on 2026-07-19 with:

- macOS 27 beta
- Xcode 27 beta 3 (`27A5218g`)
- iOS 27.0 Simulator (`24A5380i`)
- iPhone 17 Pro Simulator

In this configuration the app launches normally. The M1 iPhone flow was exercised through Day switching, Map/List switching, Activity selection, map-pin selection, and preservation of the selected Activity when moving from the map back to the list.
