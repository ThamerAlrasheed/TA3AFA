#!/bin/bash
BUNDLE_ID="com.yourname.MedAi.MEDSAI-"
APP_CONTAINER=$(xcrun simctl get_app_container booted "$BUNDLE_ID" data)
PREF="$APP_CONTAINER/Library/Preferences/$BUNDLE_ID"

echo "Reading deviceToken:"
defaults read "$PREF" deviceToken
