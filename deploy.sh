#!/bin/bash
set -e

source .env 

echo "Building Android..."
flutter build apk --release

echo "Building iOS..."
flutter build ipa

echo "Uploading to Firebase..."
firebase appdistribution:distribute \
  build/app/outputs/flutter-apk/app-release.apk \
  --app $FIREBASE_ANDROID_APP_ID \
  --release-notes "$1" \

echo "Uploading to TestFlight..."
xcrun altool --upload-app \
  -f build/ios/ipa/nodisaar.ipa \
  -t ios \
  --apiKey $ASC_KEY_ID \
  --apiIssuer $ASC_ISSUER_ID

echo "Done! 🚀"