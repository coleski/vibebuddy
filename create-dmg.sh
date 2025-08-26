#!/bin/bash

# Build the app in Release mode
echo "Building Hex in Release mode..."
xcodebuild -scheme Hex -configuration Release -derivedDataPath build

# Check if build succeeded
if [ ! -d "build/Build/Products/Release/Hex.app" ]; then
    echo "Build failed! Make sure to trust macros in Xcode first."
    echo "Open the project in Xcode: open Hex.xcodeproj"
    exit 1
fi

# Create a temporary directory for DMG contents
echo "Preparing DMG contents..."
mkdir -p dmg-contents
cp -R build/Build/Products/Release/Hex.app dmg-contents/

# Create DMG
echo "Creating DMG..."
hdiutil create -volname "Hex" -srcfolder dmg-contents -ov -format UDZO Hex-dev.dmg

# Clean up
rm -rf dmg-contents

echo "✅ DMG created: Hex-dev.dmg"
echo "You can now install and test this DMG on your Mac"