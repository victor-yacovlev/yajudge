#!/bin/sh
# Downloads WASM locally and use local fonts
# Temporary solution until https://github.com/flutter/flutter/issues/70101 and 77580 provide a better way

UNAME=$(uname -s)
if [ $UNAME == 'Darwin' ]
then
  SED=gsed
else
  SED=sed
fi

wasmLocation=$(grep canvaskit-wasm build/web/main.dart.js | $SED -e 's/.*https/https/' -e 's/bin.*/bin/' | uniq)
echo "Downloading WASM from $wasmLocation"
curl -o build/web/canvaskit.js "$wasmLocation/canvaskit.js"
curl -o build/web/canvaskit.wasm "$wasmLocation/canvaskit.wasm"
curl -o "build/web/Roboto-Regular.ttf" "https://fonts.gstatic.com/s/roboto/v20/KFOmCnqEu92Fr1Me5WZLCzYlKw.ttf"
curl -o "build/web/Noto-Sans-Symbols.css" "https://fonts.googleapis.com/css2?family=Noto+Sans+Symbols"
curl -o "build/web/Noto-Color-Emoji-Compat.css" "https://fonts.googleapis.com/css2?family=Noto+Color+Emoji+Compat"

$SED -e "s!$wasmLocation!.!" \
 -e "s!https://fonts.gstatic.com/s/roboto/v20/KFOmCnqEu92Fr1Me5WZLCzYlKw.ttf!./Roboto-Regular.ttf!" \
 -e "s!https://fonts.googleapis.com/css2?family=Noto+Sans+Symbols!./Noto-Sans-Symbols.css!" \
 -e "s!https://fonts.googleapis.com/css2?family=Noto+Color+Emoji+Compat!./Noto-Color-Emoji-Compat.css!" \
 -i \
 build/web/main.dart.js
