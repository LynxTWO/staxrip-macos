# Signing and CI setup
Version: 0.1 Draft. Date: 2026-09-28.

## What is already unblocked

The owner requested public visibility and the repository is now public: https://github.com/LynxTWO/staxrip-macos . The previously billing-blocked workflow was retried and succeeded: https://github.com/LynxTWO/staxrip-macos/actions/runs/36378725531 . Its macos-15 job installed FFmpeg and ran swift test. This verifies that workflow at the tested commit; it does not promise every future account or runner configuration will be free.

Standard GitHub-hosted runners for public repositories and self-hosted runner usage are free under the current documented policy: https://docs.github.com/en/billing/concepts/product-billing/github-actions . Larger runners and other metered services have different rules.

Local swift test and build.command can run without GitHub billing or a runner registration. A self-hosted Actions runner is optional if GitHub orchestration is needed. Do not register the everyday Mac with signing keys for public pull-request execution. Use hosted disposable jobs for contributions. If specialized hardware later requires self-hosting, use an isolated disposable environment with no personal data or signing credentials, restricted triggers and reviewed code. GitHub security guidance: https://docs.github.com/en/actions/reference/security/secure-use . No runner was installed or registered by this plan.

Proposed follow-up in production qualification: pin workflow actions to reviewed commit SHAs, separate trusted signing from PR checks, record tool versions, upload redacted evidence and require applicable fixture gates. Current workflow uses a moving checkout version and Homebrew tooling; a pass alone is not a reproducible release manifest.

## Owner setup in Xcode

Update on 2026-09-28: the owner created a Developer ID Application certificate, which was imported and verified as a valid local signing identity. The owner configured the staxrip-notary Keychain profile, and notarytool history authenticated successfully. No submission was made. The instructions below are retained for future setup; credentials are no longer a blocker.

1. In Xcode Settings, open Accounts / Apple Accounts, select the Apple Account and the team enrolled in the Apple Developer Program. A free Personal Team is insufficient for this distribution route.
2. Open Manage Certificates and create a Developer ID Application certificate. Apple's documented required role for this certificate is Account Holder; if the option is missing, check team membership and ask the Account Holder to create it through the supported team process. Do not share the private key in chat or Git.
3. Confirm locally with `security find-identity -v -p codesigning`. The expected identity begins with Developer ID Application. Xcode can create the identity in Keychain; the existing Swift Package app can use it with codesign without converting the project into an Xcode project.
4. For notarization, create an app-specific password through the Apple Account security page yourself. In a private local terminal run `xcrun notarytool store-credentials "staxrip-notary"` and follow the prompts for Apple Account, Team ID and password. This stores a Keychain profile; never put the password in a command argument, repository, CI log or chat. App Store Connect API credentials are an alternative if a later team workflow needs them.
5. Tell the project maintainer that the Developer ID identity and notary profile are ready. Do not send the credentials themselves. Enrollment or payment, if required, is an owner account action.

Apple references: https://developer.apple.com/help/account/certificates/create-developer-id-certificates and https://developer.apple.com/developer-id/ . Developer ID Application signs the app. Developer ID Installer is needed for a signed installer package, not the planned app ZIP route.

## Later release gate

For an explicitly approved release commit: build optimized bundle; sign all required nested executable code with hardened runtime, a secure timestamp and reviewed entitlements; verify signature; submit the packaged app with notarytool and wait for acceptance; staple and validate the app ticket; regenerate the downloadable archive from the stapled bundle; verify Gatekeeper behavior on a clean Mac. Record the app hash, tools and acceptance evidence. Keep signing credentials out of untrusted jobs. Existing ad-hoc developer previews are not notarized releases.

The initial planning turn made no credential changes. The subsequent owner-directed setup established the signing identity and Keychain profile as described above. No notarization upload, paid enrollment, merge or release was performed. Public source still needs an explicit project license decision.
