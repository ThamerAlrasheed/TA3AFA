#!/bin/bash
BUNDLE_ID="com.yourname.MedAi.MEDSAI-"
APP_CONTAINER=$(xcrun simctl get_app_container booted "$BUNDLE_ID" data)
PREF="$APP_CONTAINER/Library/Preferences/$BUNDLE_ID"

xcrun simctl terminate booted "$BUNDLE_ID" 2>/dev/null

defaults write "$PREF" deviceToken "legacy-device-token-123"
defaults write "$PREF" patientUserId "11111111-1111-1111-1111-111111111111"
defaults write "$PREF" activePatientId "22222222-2222-2222-2222-222222222222"
defaults write "$PREF" activePatientName "Legacy Patient"
defaults write "$PREF" userRole "patient"

xcrun simctl spawn booted killall cfprefsd
