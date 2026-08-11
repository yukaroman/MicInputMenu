#!/bin/zsh

set -euo pipefail

script_directory="${0:A:h}"
project_directory="${script_directory:h}"
output_directory="${1:-${project_directory}/dist}"
app_path="${output_directory}/MicInputMenu.app"
archive_path="${output_directory}/MicInputMenu.zip"
icon_work_directory="${project_directory}/.build/MicInputMenuIcon"
universal_work_directory="${project_directory}/.build/MicInputMenuUniversal"
signing_identity="${MIC_INPUT_SIGNING_IDENTITY:--}"
notary_profile="${MIC_INPUT_NOTARY_PROFILE:-}"
notary_keychain="${MIC_INPUT_NOTARY_KEYCHAIN:-}"

cd "${project_directory}"

if [[ "${MIC_INPUT_NATIVE_ONLY:-0}" == "1" ]]; then
    swift build -c release --product MicInputMenu
    binary_directory="$(swift build -c release --show-bin-path)"
    binary_path="${binary_directory}/MicInputMenu"
else
    arm_triple="arm64-apple-macosx13.0"
    intel_triple="x86_64-apple-macosx13.0"

    swift build -c release --triple "${arm_triple}" --product MicInputMenu
    arm_binary_directory="$(swift build -c release --triple "${arm_triple}" --show-bin-path)"

    swift build -c release --triple "${intel_triple}" --product MicInputMenu
    intel_binary_directory="$(swift build -c release --triple "${intel_triple}" --show-bin-path)"

    if [[ "${universal_work_directory}" != */.build/MicInputMenuUniversal ]]; then
        print -u2 "Refusing to replace an unexpected universal build path: ${universal_work_directory}"
        exit 1
    fi
    rm -rf -- "${universal_work_directory}"
    mkdir -p "${universal_work_directory}"
    lipo -create \
        "${arm_binary_directory}/MicInputMenu" \
        "${intel_binary_directory}/MicInputMenu" \
        -output "${universal_work_directory}/MicInputMenu"
    binary_path="${universal_work_directory}/MicInputMenu"
fi

if [[ "${app_path}" != */MicInputMenu.app || "${app_path}" == "/MicInputMenu.app" ]]; then
    print -u2 "Refusing to replace an unexpected app path: ${app_path}"
    exit 1
fi

if [[ "${icon_work_directory}" != */.build/MicInputMenuIcon ]]; then
    print -u2 "Refusing to replace an unexpected icon work path: ${icon_work_directory}"
    exit 1
fi

rm -rf -- "${app_path}" "${icon_work_directory}"
rm -f -- "${archive_path}"
mkdir -p \
    "${app_path}/Contents/MacOS" \
    "${app_path}/Contents/Resources" \
    "${icon_work_directory}/AppIcon.iconset"

swift "${project_directory}/Scripts/generate_app_icon.swift" \
    "${icon_work_directory}/AppIcon-1024.png"

for specification in \
    "16 icon_16x16.png" \
    "32 icon_16x16@2x.png" \
    "32 icon_32x32.png" \
    "64 icon_32x32@2x.png" \
    "128 icon_128x128.png" \
    "256 icon_128x128@2x.png" \
    "256 icon_256x256.png" \
    "512 icon_256x256@2x.png" \
    "512 icon_512x512.png" \
    "1024 icon_512x512@2x.png"
do
    size="${specification%% *}"
    filename="${specification#* }"
    sips -z "${size}" "${size}" \
        "${icon_work_directory}/AppIcon-1024.png" \
        --out "${icon_work_directory}/AppIcon.iconset/${filename}" >/dev/null
done

iconutil -c icns \
    "${icon_work_directory}/AppIcon.iconset" \
    -o "${app_path}/Contents/Resources/AppIcon.icns"

install -m 755 "${binary_path}" "${app_path}/Contents/MacOS/MicInputMenu"
install -m 644 "${project_directory}/Resources/Info.plist" "${app_path}/Contents/Info.plist"

if [[ "${signing_identity}" == "-" ]]; then
    codesign --force --deep --sign - --timestamp=none "${app_path}"
else
    codesign \
        --force \
        --deep \
        --options runtime \
        --timestamp \
        --sign "${signing_identity}" \
        "${app_path}"
fi

codesign --verify --deep --strict "${app_path}"
ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${archive_path}"

if [[ -n "${notary_profile}" ]]; then
    if [[ "${signing_identity}" == "-" ]]; then
        print -u2 "Notarization requires MIC_INPUT_SIGNING_IDENTITY."
        exit 1
    fi
    if ! xcrun --find notarytool >/dev/null 2>&1; then
        print -u2 "notarytool is unavailable. Install full Xcode to notarize."
        exit 1
    fi

    notary_arguments=(--keychain-profile "${notary_profile}")
    if [[ -n "${notary_keychain}" ]]; then
        notary_arguments+=(--keychain "${notary_keychain}")
    fi
    xcrun notarytool submit "${archive_path}" \
        "${notary_arguments[@]}" \
        --wait
    xcrun stapler staple "${app_path}"
    rm -f -- "${archive_path}"
    ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${archive_path}"
fi

print "${app_path}"
print "${archive_path}"
