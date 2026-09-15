#!/bin/bash
# Bundled updater: all arguments are data, never evaluated as shell commands.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
umask 077

[[ $# -eq 6 ]] || exit 64
work="$1"
target="$2"
parent_pid="$3"
version="$4"
image_url="$5"
checksum_url="$6"
[[ "$parent_pid" =~ ^[1-9][0-9]*$ && "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 64
[[ -d "$work" && "$work" = /* && "$target" = /*.app && -d "$target" && ! -L "$target" ]] || exit 64
[[ "$target" != /Volumes/* && "$target" != */AppTranslocation/* ]] || exit 64
[[ -w "$target" && -w "$(dirname "$target")" ]] || exit 73

mount="$work/mount"
stage=""
backup=""
replaced=0
finished=0
cleanup() {
    code=$?
    trap - EXIT
    if [[ "$finished" -eq 0 && -n "$backup" && -d "$backup/previous.app" ]]; then
        if [[ "$replaced" -eq 1 && -d "$target" ]]; then
            /bin/mv "$target" "$backup/failed.app" || true
        fi
        if [[ ! -e "$target" ]]; then
            /bin/mv "$backup/previous.app" "$target" || true
        fi
        /usr/bin/open "$target" || true
    fi
    /usr/bin/hdiutil detach "$mount" -quiet 2>/dev/null || true
    [[ -z "$stage" ]] || /bin/rm -rf "$stage"
    # Never delete the only remaining copy if rollback itself failed.
    if [[ -n "$backup" && ! -d "$backup/previous.app" ]]; then
        /bin/rm -rf "$backup"
    fi
    /bin/rm -rf "$work"
    if [[ "$code" -ne 0 ]]; then
        echo "Update failed (exit $code). Any recoverable previous app was restored."
        if ! /bin/kill -0 "$parent_pid" 2>/dev/null; then
            /usr/bin/osascript -e 'display alert "Hugging Face update failed" message "Please reopen Hugging Face or reinstall from GitHub Releases. Details are in ~/Library/Logs/Hugging Face/Update.log." as critical' || true
        fi
    fi
    exit "$code"
}
trap cleanup EXIT

echo "Downloading Hugging Face $version"
/usr/bin/curl --fail --location --proto '=https' --proto-redir '=https' --connect-timeout 30 --max-time 1800 --retry 2 --output "$work/update.dmg" "$image_url"
/usr/bin/curl --fail --location --proto '=https' --proto-redir '=https' --connect-timeout 30 --max-time 120 --retry 2 --output "$work/checksum" "$checksum_url"
expected="$(/usr/bin/awk 'NR == 1 { print $1 }' "$work/checksum")"
[[ "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || { echo "Invalid checksum file"; exit 65; }
actual="$(/usr/bin/shasum -a 256 "$work/update.dmg" | /usr/bin/awk '{ print $1 }')"
[[ "$(echo "$expected" | /usr/bin/tr 'A-F' 'a-f')" == "$actual" ]] || { echo "Checksum mismatch"; exit 65; }

/bin/mkdir "$mount"
/usr/bin/hdiutil attach "$work/update.dmg" -readonly -nobrowse -mountpoint "$mount" -quiet
candidate="$mount/Hugging Face.app"
plist="$candidate/Contents/Info.plist"
[[ -d "$candidate" && ! -L "$candidate" ]] || exit 65
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" == "ehcalabres.HuggingFace" ]] || exit 65
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" == "$version" ]] || exit 65
/usr/bin/codesign --verify --deep --strict "$candidate"
minimum="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")"
current="$(/usr/bin/sw_vers -productVersion)"
/usr/bin/awk -v current="$current" -v minimum="$minimum" 'BEGIN {
    split(current, a, "."); split(minimum, b, ".");
    for (i = 1; i <= 3; i++) {
        if (a[i] + 0 > b[i] + 0) exit 0;
        if (a[i] + 0 < b[i] + 0) exit 1;
    }
}' || { echo "This update requires macOS $minimum or later"; exit 65; }

# Stage on the destination volume so replacement uses same-volume renames.
stage="$(/usr/bin/mktemp -d "$(dirname "$target")/.hugging-face-update.XXXXXX")"
/usr/bin/ditto "$candidate" "$stage/Hugging Face.app"
/usr/bin/codesign --verify --deep --strict "$stage/Hugging Face.app"
/usr/bin/hdiutil detach "$mount" -quiet
/usr/bin/touch "$work/ready"
echo "Verified update. Waiting for the app to exit."
for ((attempt = 0; attempt < 120; attempt++)); do
    if ! /bin/kill -0 "$parent_pid" 2>/dev/null; then break; fi
    /bin/sleep 1
done
if /bin/kill -0 "$parent_pid" 2>/dev/null; then
    echo "App did not exit; update cancelled."
    exit 75
fi

backup="$(/usr/bin/mktemp -d "$(dirname "$target")/.hugging-face-backup.XXXXXX")"
/bin/mv "$target" "$backup/previous.app"
/bin/mv "$stage/Hugging Face.app" "$target"
replaced=1
/usr/bin/open "$target"
finished=1
/bin/rm -rf "$backup"
echo "Installed Hugging Face $version"
