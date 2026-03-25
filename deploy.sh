#!/bin/bash
set -e

source .env 

echo "Building Android..."
flutter build apk --split-per-abi --release

echo "Building iOS..."
flutter build ipa

echo "Uploading to Firebase..."
gcloud storage cp \
  build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
  gs://nodi-saar.firebasestorage.app/releases/nodisaar-latest.apk

gcloud storage objects update \
  gs://nodi-saar.firebasestorage.app/releases/nodisaar-latest.apk \
  --add-acl-grant=entity=allUsers,role=READER

echo "Uploading to TestFlight..."
xcrun altool --upload-app \
  -f build/ios/ipa/nodisaar.ipa \
  -t ios \
  --apiKey $ASC_KEY_ID \
  --apiIssuer $ASC_ISSUER_ID

echo "Done! 🚀"