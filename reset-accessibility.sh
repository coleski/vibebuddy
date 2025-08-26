#!/bin/bash

# Reset accessibility permissions for Hex app
# Run this after building to avoid manual permission clearing

BUNDLE_ID="com.kitlangton.Hex"

echo "Resetting accessibility permissions for $BUNDLE_ID..."

# Remove the app from accessibility database
tccutil reset Accessibility $BUNDLE_ID

# For development builds, also reset using the full path
APP_PATH="$HOME/Library/Developer/Xcode/DerivedData/Hex-*/Build/Products/Debug/Hex.app"
if [ -d "$APP_PATH" ]; then
    tccutil reset Accessibility "$APP_PATH"
fi

echo "Accessibility permissions reset. The app will request permissions on next launch."