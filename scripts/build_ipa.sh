#!/usr/bin/env bash
# Собирает неподписанный IPA для сайдлоада (AltStore / Sideloadly подпишут своим сертификатом).
#   ./scripts/build_ipa.sh            → build/FiberNavi.ipa
# Нужны: macOS, Xcode 16+, xcodegen (brew install xcodegen).
# Паки из Assets/UserPacks попадают внутрь IPA — положи их до сборки.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build
ARCHIVE="$OUT/FiberNavi.xcarchive"
rm -rf "$OUT" && mkdir -p "$OUT"

command -v xcodegen >/dev/null || { echo "Нужен xcodegen: brew install xcodegen" >&2; exit 1; }
xcodegen generate --quiet

xcodebuild archive \
  -project FiberNavi.xcodeproj \
  -scheme FiberNavi \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  | (command -v xcbeautify >/dev/null && xcbeautify || cat)

APP="$ARCHIVE/Products/Applications/FiberNavi.app"
[[ -d "$APP" ]] || { echo "Нет $APP — архив не собрался" >&2; exit 1; }

mkdir -p "$OUT/Payload"
cp -R "$APP" "$OUT/Payload/"
(cd "$OUT" && zip -qry FiberNavi.ipa Payload)
rm -rf "$OUT/Payload"

SIZE=$(du -h "$OUT/FiberNavi.ipa" | cut -f1)
echo "Готово: $OUT/FiberNavi.ipa ($SIZE). Открой в Sideloadly или AltStore."
