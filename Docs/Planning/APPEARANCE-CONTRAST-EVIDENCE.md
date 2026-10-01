# Semantic appearance evidence

Slice 034 under D-061 / R-043 is approved for build, not yet accepted.

The original fixed teal has sRGB contrast 2.396:1 on white and 2.049:1 on a 0.93 neutral surface; on a 0.12 dark surface it has 6.912:1. This makes one constant unsuitable for small active text in both appearances. Candidate reference colors and tint math were evaluated before implementation.

[W3C contrast guidance](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html) informs the 4.5:1 small-text design benchmark; this is not a whole native-app conformance claim. [Apple's dynamic color provider](https://developer.apple.com/documentation/appkit/nscolor/init(name:dynamicprovider:)) resolves a color using the supplied drawing appearance. [Apple's increased-contrast appearance guidance](https://developer.apple.com/documentation/appkit/nsappearance/name-swift.struct/accessibilityhighcontrastdarkaqua) says AppKit derives that appearance from the user's setting; the app must not force it on views. Reference tests may resolve it directly without changing system preferences.

Need: readable app-owned text and action labels. Authority: owner design delegation, D-061 / R-043. Worst case: faint status or action text makes correction difficult; consequence is presentation only, with action guards and encoding untouched. The simplest change is one shared dynamic palette and a shared native prominent modifier, not a new theme subsystem. No runtime telemetry or media processing is added. Existing primary/secondary system labels and chart-series colors keep their separate meanings.
