#!/bin/zsh
set -eu

# Moves every dylib in an iOS app's Frameworks folder into a framework of its own, because the App Store refuses
# loose dylibs in an iOS app, and points the app and the other libraries at the new paths.
if (( $# != 2 )); then
    echo 'usage: frameworkify-ios.sh APP_DIR BUNDLE_ID' >&2
    exit 1
fi
app_dir="$1"
bundle_id="$2"
frameworks_dir="$app_dir/Frameworks"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_dir/Info.plist")"
minimum="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$app_dir/Info.plist")"

typeset -A renamed
for library in "$frameworks_dir"/*.dylib(N); do
    file="${library:t}"
    name="${${${file#lib}%.dylib}//./}"
    framework="$frameworks_dir/$name.framework"
    mkdir -p "$framework"
    mv "$library" "$framework/$name"
    install_name_tool -id "@rpath/$name.framework/$name" "$framework/$name"
    cat > "$framework/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$name</string>
<key>CFBundleIdentifier</key><string>$bundle_id.framework.$name</string>
<key>CFBundleName</key><string>$name</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$build</string>
<key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
<key>MinimumOSVersion</key><string>$minimum</string>
</dict></plist>
PLIST
    renamed[$file]="$name"
done

mach_o_files=("$app_dir/ChiakiNG")
for file name in "${(@kv)renamed}"; do
    mach_o_files+=("$frameworks_dir/$name.framework/$name")
done
for mach_o in "${mach_o_files[@]}"; do
    changes=()
    for dependency in "${(@f)$(otool -L "$mach_o" | tail -n +2 | awk '{print $1}')}"; do
        if [[ "$dependency" == @rpath/* && -n "${renamed[${dependency:t}]-}" ]]; then
            name="${renamed[${dependency:t}]}"
            changes+=(-change "$dependency" "@rpath/$name.framework/$name")
        fi
    done
    if (( ${#changes} > 0 )); then
        install_name_tool "${changes[@]}" "$mach_o"
    fi
    if [[ "$mach_o" != "$app_dir/ChiakiNG" ]] && ! otool -l "$mach_o" | grep -A2 LC_RPATH | grep -q '@loader_path/\.\.'; then
        install_name_tool -add_rpath @loader_path/.. "$mach_o"
    fi
done
if ! otool -l "$app_dir/ChiakiNG" | grep -A2 LC_RPATH | grep -q '@executable_path/Frameworks'; then
    install_name_tool -add_rpath @executable_path/Frameworks "$app_dir/ChiakiNG"
fi
for mach_o in "${mach_o_files[@]}"; do
    for dependency in "${(@f)$(otool -L "$mach_o" | tail -n +2 | awk '{print $1}')}"; do
        if [[ "$dependency" == *.dylib && "$dependency" != /usr/lib/* && "$dependency" != /System/* ]]; then
            echo "$mach_o still links the loose library $dependency" >&2
            exit 1
        fi
    done
done
printf 'Wrapped %d libraries as frameworks\n' "${#renamed}"
