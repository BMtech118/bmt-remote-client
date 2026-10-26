#!/bin/bash
# Applies the BMT Remote branding to a RustDesk source tree (run from the repo
# root on macOS; uses sips). The server address, key and app name live in the
# hbb_common fork (BMtech118/bmt-remote-hbb-common, branch bmt).
# RustDesk is AGPL-3.0: this fork's source stays public, the original
# copyright notices are kept, and none of RustDesk's names or logos are used
# as our branding.
set -euo pipefail
B=branding
cp $B/BMT_Remote_Windows.ico res/icon.ico
cp $B/BMT_Remote_Windows.ico flutter/windows/runner/resources/app_icon.ico
cp $B/BMT_Remote_macOS.icns flutter/macos/Runner/AppIcon.icns
cp $B/BMT_Remote_Icon_1024.png res/icon.png
cp $B/BMT_Remote_Icon_1024.png res/mac-icon.png
cp $B/BMT_Remote_Icon_32.png res/32x32.png
cp $B/BMT_Remote_Icon_64.png res/64x64.png
cp $B/BMT_Remote_Icon_128.png res/128x128.png
cp $B/BMT_Remote_Icon_256.png res/128x128@2x.png
cp $B/BMT_Remote_App_Icon.svg flutter/assets/icon.svg
# In-app header logo (shown at most 300 x 60): light theme gets the navy wordmark.
sips -Z 600 $B/BMT_Remote_Logo_Light.png --out flutter/assets/logo_light.png >/dev/null
sips -Z 600 $B/BMT_Remote_Logo_Dark.png --out flutter/assets/logo_dark.png >/dev/null
cp flutter/assets/logo_light.png flutter/assets/logo.png

python3 - <<'PY'
import re
def edit(path, pairs):
    s = open(path, encoding="utf-8").read()
    for a, b in pairs:
        if b in s and a not in s:
            continue  # already applied
        if a not in s:
            raise SystemExit(f"{path}: not found: {a}")
        s = s.replace(a, b)
    open(path, "w", encoding="utf-8").write(s)

notice = "Based on RustDesk, Copyright © 2026 Purslane Tech Pte. Ltd. (AGPL-3.0). Modifications by BM Technologies Ltd."
edit("flutter/windows/runner/Runner.rc", [
    ('VALUE "CompanyName", "Purslane Tech Pte. Ltd." "\\0"', 'VALUE "CompanyName", "BM Technologies Ltd" "\\0"'),
    ('VALUE "FileDescription", "RustDesk Remote Desktop" "\\0"', 'VALUE "FileDescription", "BMT Remote Support" "\\0"'),
    ('VALUE "LegalCopyright", "Copyright © 2026 Purslane Tech Pte. Ltd. All rights reserved." "\\0"', f'VALUE "LegalCopyright", "{notice}" "\\0"'),
    ('VALUE "ProductName", "RustDesk" "\\0"', 'VALUE "ProductName", "BMT Remote" "\\0"'),
])
edit("Cargo.toml", [
    ('LegalCopyright = "Copyright © 2026 Purslane Tech Pte. Ltd. All rights reserved."', f'LegalCopyright = "{notice}"'),
    ('ProductName = "RustDesk"', 'ProductName = "BMT Remote"'),
    ('FileDescription = "RustDesk Remote Desktop"', 'FileDescription = "BMT Remote Support"'),
    ('identifier = "com.carriez.rustdesk"', 'identifier = "uk.co.bmtech.remote"'),
])
edit("flutter/macos/Runner/Configs/AppInfo.xcconfig", [
    ("PRODUCT_NAME = RustDesk", "PRODUCT_NAME = BMT Remote"),
    ("PRODUCT_BUNDLE_IDENTIFIER = com.carriez.flutterHbb", "PRODUCT_BUNDLE_IDENTIFIER = uk.co.bmtech.remote"),
    ("PRODUCT_COPYRIGHT = Copyright © 2026 Purslane Tech Pte. Ltd. All rights reserved.", f"PRODUCT_COPYRIGHT = {notice}"),
])
# Link scheme: the app name has a space, so the scheme drops it (bmtremote://);
# "bmt remote://" is not a valid URL and one-click connect links would fail.
edit("src/common.rs", [
    ('format!("{}://", get_app_name().to_lowercase())', "format!(\"{}://\", get_app_name().to_lowercase().replace(' ', \"\"))"),
])
edit("src/platform/windows.rs", [
    ("let ext = app_name.to_lowercase();", "let ext = app_name.to_lowercase().replace(' ', \"\");"),
])
edit("flutter/macos/Runner/Info.plist", [
    ("<string>rustdesk</string>", "<string>bmtremote</string>"),
])
# build.py hardcodes the Flutter macOS bundle as RustDesk.app; ours is "BMT Remote.app".
edit("build.py", [
    ("system2('cp -rf ../target/release/service ./build/macos/Build/Products/Release/RustDesk.app/Contents/MacOS/')",
     "system2('cp -rf ../target/release/service \"./build/macos/Build/Products/Release/BMT Remote.app/Contents/MacOS/\"')"),
    ('--icon RustDesk.app 200 190 --hide-extension RustDesk.app rustdesk.dmg ./build/macos/Build/Products/Release/RustDesk.app")',
     '--icon \\"BMT Remote.app\\" 200 190 --hide-extension \\"BMT Remote.app\\" rustdesk.dmg \\"./build/macos/Build/Products/Release/BMT Remote.app\\"")'),
    ('create-dmg --volname \\"RustDesk Installer\\"', 'create-dmg --volname \\"BMT Remote\\"'),
])
# macOS 12 minimum: current Xcode refuses older deployment targets.
edit("flutter/macos/Podfile", [
    ("platform :osx, '10.14'", "platform :osx, '12.0'"),
    ("""    flutter_additional_macos_build_settings(target)
  end""", """    flutter_additional_macos_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '12.0'
    end
  end"""),
])
p = "flutter/macos/Runner.xcodeproj/project.pbxproj"
s = open(p, encoding="utf-8").read()
s = re.sub(r"MACOSX_DEPLOYMENT_TARGET = 10\.\d+;", "MACOSX_DEPLOYMENT_TARGET = 12.0;", s)
open(p, "w", encoding="utf-8").write(s)
# Our own macOS bundle ID (the Xcode project overrides AppInfo.xcconfig), so
# macOS never treats BMT Remote as RustDesk, permissions included.
p = "flutter/macos/Runner.xcodeproj/project.pbxproj"
s = open(p, encoding="utf-8").read().replace("PRODUCT_BUNDLE_IDENTIFIER = com.carriez.rustdesk;", "PRODUCT_BUNDLE_IDENTIFIER = uk.co.bmtech.remote;")
open(p, "w", encoding="utf-8").write(s)
edit("flutter/macos/Runner/Info.plist", [("<string>com.carriez.rustdesk</string>", "<string>uk.co.bmtech.remote</string>")])
PY
echo "branding applied"
