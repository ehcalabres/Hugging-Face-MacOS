#!/bin/bash

set -euo pipefail

usage() {
    echo "Usage: $0 <version> <build-number> [output-directory]"
    echo "Example: $0 0.1.0 1 dist"
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
    usage >&2
    exit 64
fi

version="$1"
build_number="$2"
output_directory="${3:-dist}"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Version must use the X.Y.Z format (for example, 0.1.0)." >&2
    exit 64
fi

if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
    echo "Build number must be a positive integer." >&2
    exit 64
fi

script_directory="$(cd "$(dirname "$0")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"

if [[ "$output_directory" != /* ]]; then
    output_directory="$repository_root/$output_directory"
fi

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/hugging-face-release.XXXXXX")"
archive_path="$temporary_directory/Hugging Face.xcarchive"
staging_directory="$temporary_directory/dmg"
app_path="$archive_path/Products/Applications/Hugging Face.app"
binary_path="$app_path/Contents/MacOS/Hugging Face"
artifact_name="Hugging-Face-${version}.dmg"
dmg_path="$output_directory/$artifact_name"

cleanup() {
    rm -rf "$temporary_directory"
}
trap cleanup EXIT

mkdir -p "$output_directory" "$staging_directory"

echo "Archiving Hugging Face ${version} (${build_number})..."
xcodebuild archive \
    -quiet \
    -project "$repository_root/Hugging Face MacOS.xcodeproj" \
    -scheme "Hugging Face" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$archive_path" \
    -derivedDataPath "$temporary_directory/DerivedData" \
    MARKETING_VERSION="$version" \
    CURRENT_PROJECT_VERSION="$build_number" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    DEVELOPMENT_TEAM= \
    AD_HOC_CODE_SIGNING_ALLOWED=YES

if [[ ! -d "$app_path" ]]; then
    echo "The archive did not contain the expected app at: $app_path" >&2
    exit 1
fi

codesign --verify --deep --strict --verbose=2 "$app_path"

architectures="$(lipo -archs "$binary_path")"
if [[ " $architectures " != *" arm64 "* || " $architectures " != *" x86_64 "* ]]; then
    echo "Expected a universal app, but found architectures: $architectures" >&2
    exit 1
fi

plist_path="$app_path/Contents/Info.plist"
archived_version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist_path")"
archived_build="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist_path")"

if [[ "$archived_version" != "$version" || "$archived_build" != "$build_number" ]]; then
    echo "Archived version mismatch: expected ${version} (${build_number}), found ${archived_version} (${archived_build})." >&2
    exit 1
fi

ditto "$app_path" "$staging_directory/Hugging Face.app"
ln -s /Applications "$staging_directory/Applications"

rm -f "$dmg_path" "$dmg_path.sha256"

echo "Creating $artifact_name..."
hdiutil create \
    -volname "Hugging Face" \
    -srcfolder "$staging_directory" \
    -format UDZO \
    -ov \
    "$dmg_path"

hdiutil verify "$dmg_path"

(
    cd "$output_directory"
    shasum -a 256 "$artifact_name" > "$artifact_name.sha256"
)

echo "Created: $dmg_path"
echo "Checksum: $dmg_path.sha256"
