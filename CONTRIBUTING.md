# Contributing

Thanks for helping improve Hugging Face for macOS.

## Development setup

The project requires macOS 14.0 or later and a compatible version of Xcode.

1. Clone the repository.
2. Open `Hugging Face MacOS.xcodeproj` in Xcode.
3. Select the **Hugging Face** scheme and the **My Mac** destination.
4. Build and run the app.
5. Add a Hugging Face token in the app's Settings when testing authenticated features.

Before submitting a change, make sure the project builds in Xcode and avoid committing local Xcode user data, Derived Data, or generated release artifacts.

## Versioning

The app uses Apple's standard two-part versioning:

- `MARKETING_VERSION` is the user-facing semantic version, such as `0.1.0`. It becomes `CFBundleShortVersionString` in the built app.
- `CURRENT_PROJECT_VERSION` is the internal build number, such as `1`. It becomes `CFBundleVersion`.

Both values are stored in `Hugging Face MacOS.xcodeproj/project.pbxproj` and can also be changed from the target's **General → Identity** section in Xcode.

Release tags must use the `vX.Y.Z` format. The GitHub Actions workflow takes the user-facing version from the tag and uses the GitHub Actions run number as the release build number. Keeping the version in the Xcode project updated is still important so ordinary local builds report the current version.

## Building a release locally

Run the release script with a semantic version and positive build number:

```sh
./scripts/build-release.sh 0.1.0 1 dist
```

The script:

1. Creates a universal Release archive for Apple Silicon and Intel Macs.
2. Applies an ad-hoc signature while preserving the app's sandbox entitlements.
3. Verifies the signature, architectures, version, and build number.
4. Creates `dist/Hugging-Face-0.1.0.dmg` with an Applications shortcut.
5. Verifies the disk image and writes a SHA-256 checksum beside it.

Check the downloaded or locally built artifact with:

```sh
cd dist
shasum -a 256 -c Hugging-Face-0.1.0.dmg.sha256
```

## Creating a GitHub release

Use the following steps for each release:

1. Choose the next semantic version according to the size of the change: patch (`0.1.1`), minor (`0.2.0`), or major (`1.0.0`).
2. Update the target's **Version** and **Build** values in Xcode.
3. Build the DMG locally and check that it opens, contains **Hugging Face.app**, and has a working Applications shortcut.
4. Commit and push the version change to `main`.
5. Create and push an annotated tag for that exact commit:

   ```sh
   git tag -a v0.2.0 -m "Release 0.2.0"
   git push origin v0.2.0
   ```

6. Open the repository's **Actions** page and wait for the **Release DMG** workflow to finish.
7. Open **Releases** and verify that the new release contains both the DMG and its `.sha256` file.

Pushing the tag starts `.github/workflows/release.yml`. The workflow validates the tag, invokes `scripts/build-release.sh`, generates release notes, and publishes both artifacts to the matching GitHub Release. Re-running the workflow replaces existing artifacts for that tag.

## Signing and Gatekeeper

Current releases are ad-hoc signed because the project does not use a paid Apple Developer membership. They cannot be notarized and macOS identifies them as coming from an unidentified developer.

Users may need to Control-click the installed app and choose **Open** on first launch, or allow it from **System Settings → Privacy & Security**. A future Developer ID certificate and notarization step can be added to the workflow without changing the versioning or tagging process.
