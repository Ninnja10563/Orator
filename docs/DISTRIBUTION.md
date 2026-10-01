# Signing and distribution

The normal macOS workflow produces an ad-hoc signed Apple Silicon development build. The separate **Signed macOS distribution** workflow builds with hardened runtime, exercises the signed app, submits it to Apple, staples the accepted tickets, verifies Gatekeeper acceptance, and packages a ZIP and a drag-to-Applications DMG with SHA-256 checksums. It does not publish a GitHub Release automatically.

## One-time Apple setup

An Apple Developer Program account is required. Export a **Developer ID Application** certificate and its private key from Keychain Access as a password-protected `.p12`. A Mac Distribution certificate is not interchangeable. Create an App Store Connect team API key authorized for notarization.

Configure these GitHub Actions secrets in the repository's `distribution` environment (or repository secrets). Never commit the files or paste their contents into an issue or chat:

| Secret | Value |
|---|---|
| `APPLE_CERTIFICATE_P12_BASE64` | Base64 encoding of the exported certificate/private key `.p12` |
| `APPLE_CERTIFICATE_PASSWORD` | Password protecting the `.p12` |
| `APPLE_SIGN_IDENTITY` | Full Developer ID Application identity, including team ID |
| `APPLE_NOTARY_KEY_P8` | Contents of the App Store Connect private `.p8` key |
| `APPLE_NOTARY_KEY_ID` | API key identifier |
| `APPLE_NOTARY_ISSUER` | Team API issuer UUID |

Run **Actions → Signed macOS distribution → Run workflow** for the commit being distributed. Missing credentials fail the workflow explicitly; ad-hoc builds are never relabeled as notarized. The ephemeral runner keychain and imported private key files are removed in the cleanup step.

Download `Orator-notarized-macOS-arm64` only after the workflow succeeds. Check the version in the app's About window and verify the included checksums. Attach the resulting files to a release only after the acceptance checks in `DEVELOPMENT.md` are complete. Production signing and Apple acceptance have not been exercised until this credentialed workflow succeeds.

See Apple's [notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) and [custom workflow documentation](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
