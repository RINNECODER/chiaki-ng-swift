#!/bin/zsh
set -eu

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
signing_dir="$project_dir/.local-signing"
mode="${1:-ipa}"
case "$mode" in
    ipa|upload) ;;
    *) echo 'usage: app-store-ios.sh ipa|upload' >&2; exit 1 ;;
esac
bundle_id=io.github.chiaki-ng.chiaki-ng.appstore
app="$project_dir/.build/app-store-ios/chiaki-ng.app"

setting() {
    local value="$1" file="$signing_dir/$2"
    if [[ -z "$value" && -f "$file" ]]; then
        value="$(cat "$file")"
    fi
    printf '%s' "$value"
}

identity="$(setting "${CHIAKI_APP_STORE_IDENTITY:-}" app-store-identity)"
if [[ -z "$identity" ]]; then
    identity="$(security find-identity -v -p codesigning | grep -F 'Apple Distribution' | head -1 | awk '{print $2}')"
fi
if [[ -z "$identity" ]]; then
    echo 'No Apple Distribution identity found; set CHIAKI_APP_STORE_IDENTITY.' >&2
    exit 1
fi
profile="${CHIAKI_IOS_APP_STORE_PROFILE:-$signing_dir/ios-app-store.mobileprovision}"
if [[ ! -f "$profile" ]]; then
    echo "No iOS App Store provisioning profile at $profile; set CHIAKI_IOS_APP_STORE_PROFILE." >&2
    exit 1
fi

CHIAKI_APP_STORE=1 CHIAKI_PLATFORM=ios CHIAKI_LAUNCH_APP=0 CONFIGURATION=release \
    CHIAKI_VERSION_TAG="${CHIAKI_VERSION_TAG:-}" SWIFT="${SWIFT:-swift}" "$project_dir/Scripts/run-ios.sh"

work_dir="$(mktemp -d "$project_dir/.build/app-store-ios/sign.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

# The App Store refuses loose dylibs in an iOS app, so each one becomes a framework of the same name.
"$project_dir/Tools/Packaging/frameworkify-ios.sh" "$app" "$bundle_id"

# The App Store reads the iOS icon from a compiled asset catalog, not from loose files.
icon="$(print -l "$app"/AppIcon1024x1024*.png(N) | head -1)"
if [[ -z "$icon" ]]; then
    echo "No 1024 pt icon in $app" >&2
    exit 1
fi
catalog="$work_dir/Assets.xcassets"
mkdir -p "$catalog/AppIcon.appiconset"
cp "$icon" "$catalog/AppIcon.appiconset/AppIcon.png"
print '{"info":{"author":"xcode","version":1}}' > "$catalog/Contents.json"
print '{"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}' \
    > "$catalog/AppIcon.appiconset/Contents.json"
rm -f "$app"/AppIcon*.png
xcrun actool "$catalog" --compile "$app" --platform iphoneos --minimum-deployment-target 26.0 \
    --target-device iphone --target-device ipad --app-icon AppIcon \
    --output-partial-info-plist "$work_dir/icons.plist" --output-format human-readable-text > "$work_dir/actool.log"
/usr/libexec/PlistBuddy -c 'Delete :CFBundleIcons' -c 'Delete :CFBundleIcons~ipad' "$app/Info.plist"
/usr/libexec/PlistBuddy -c "Merge $work_dir/icons.plist" "$app/Info.plist"

# App Store Connect checks the SDK and Xcode an app was built with.
sdk_version="$(xcrun --sdk iphoneos --show-sdk-version)"
sdk_build="$(xcrun --sdk iphoneos --show-sdk-build-version)"
xcode_version="$(xcodebuild -version | awk '/^Xcode/ {print $2}')"
xcode_build="$(xcodebuild -version | awk '/^Build version/ {print $3}')"
xcode_parts=(${(s:.:)xcode_version} 0 0)
xcode_number="$(printf '%d%d%d' "${xcode_parts[1]}" "${xcode_parts[2]}" "${xcode_parts[3]}")"
for entry in "DTPlatformName string iphoneos" "DTPlatformVersion string $sdk_version" \
        "DTPlatformBuild string $sdk_build" "DTSDKName string iphoneos$sdk_version" "DTSDKBuild string $sdk_build" \
        "DTXcode string $xcode_number" "DTXcodeBuild string $xcode_build" "UIRequiredDeviceCapabilities array"; do
    /usr/libexec/PlistBuddy -c "Delete :${entry%% *}" "$app/Info.plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :$entry" "$app/Info.plist"
done
/usr/libexec/PlistBuddy -c 'Add :UIRequiredDeviceCapabilities: string arm64' "$app/Info.plist"

security cms -D -i "$profile" > "$work_dir/profile.plist"
application_id="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$work_dir/profile.plist")"
team_id="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' "$work_dir/profile.plist")"
if [[ "$application_id" != "$team_id.$bundle_id" ]]; then
    echo "The provisioning profile is for $application_id, not $team_id.$bundle_id." >&2
    exit 1
fi
if /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$work_dir/profile.plist" >/dev/null 2>&1; then
    echo "The provisioning profile at $profile lists devices, so it is not an App Store profile." >&2
    exit 1
fi
entitlements="$work_dir/ChiakiNG.entitlements"
/usr/libexec/PlistBuddy -x -c 'Print :Entitlements' "$work_dir/profile.plist" > "$entitlements"
cp -X "$profile" "$app/embedded.mobileprovision"
xattr -cr "$app"

for framework in "$app"/Frameworks/*.framework(N); do
    codesign --force --timestamp --sign "$identity" "$framework"
done
codesign --force --timestamp --entitlements "$entitlements" --sign "$identity" "$app"
codesign --verify --deep --strict --verbose=2 "$app"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Info.plist")"
mkdir -p "$project_dir/dist" "$work_dir/ipa/Payload"
ditto "$app" "$work_dir/ipa/Payload/chiaki-ng.app"
package="$project_dir/dist/chiaki-ng-$version-$build-AppStore.ipa"
rm -f "$package"
(cd "$work_dir/ipa" && ditto -c -k --sequesterRsrc --keepParent Payload "$package")
printf 'Built %s\n' "$package"
if [[ "$mode" != upload ]]; then
    exit 0
fi

key_files=("$signing_dir"/AuthKey_*.p8(N))
key_id="${CHIAKI_API_KEY_ID:-}"
if [[ -z "$key_id" && ${#key_files} == 1 ]]; then
    key_id="${${key_files[1]:t:r}#AuthKey_}"
fi
issuer="$(setting "${CHIAKI_API_ISSUER:-}" app-store-issuer)"
if [[ -z "$key_id" || -z "$issuer" ]]; then
    echo 'Set CHIAKI_API_KEY_ID and CHIAKI_API_ISSUER, or put one AuthKey_<id>.p8 and app-store-issuer in .local-signing.' >&2
    exit 1
fi
export API_PRIVATE_KEYS_DIR="$signing_dir"
xcrun altool --validate-app "$package" --platform ios --api-key "$key_id" --api-issuer "$issuer"
xcrun altool --upload-package "$package" --platform ios --api-key "$key_id" --api-issuer "$issuer"
