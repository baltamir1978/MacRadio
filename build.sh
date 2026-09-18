#!/bin/bash
# Compila MacRadio (app + widget) en Release, firmado con Developer ID.
#
# Uso:  ./build.sh             compila en build/
#       ./build.sh --install   compila, la instala en /Applications y la abre
#
# El proyecto de Xcode se regenera antes con Tools/generate_project.rb: es un resultado, no
# una fuente, así que cualquier cambio de ajustes va en ese script.

set -euo pipefail
cd "$(dirname "$0")"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
APP="build/dd/Build/Products/Release/MacRadio.app"

ruby Tools/generate_project.rb >/dev/null
python3 Tools/translations.py check >/dev/null || { echo "Hay cadenas sin traducir: python3 Tools/translations.py check"; exit 1; }
python3 Tools/translations.py >/dev/null

echo "Compilando…"
# Sin la copia anterior, un fallo de compilación no pasa por bueno ni se instala.
rm -rf "$APP"
xcodebuild -project MacRadio.xcodeproj -scheme MacRadio -configuration Release \
    -derivedDataPath build/dd build 2>&1 | grep -E "error:|warning:|BUILD" || true
[[ -d "$APP" ]] || { echo "La compilación ha fallado."; exit 1; }
codesign --verify --deep --strict "$APP"
echo "✓ $APP"

if [[ "${1:-}" == "--install" ]]; then
    osascript -e 'quit app "MacRadio"' 2>/dev/null || true
    sleep 1
    rm -rf /Applications/MacRadio.app
    ditto "$APP" /Applications/MacRadio.app
    # Que el sistema no ofrezca el widget de una copia de compilación: solo el instalado.
    for copy in build/dd/Build/Products/*/MacRadio.app; do
        "$LSREGISTER" -u "$copy" 2>/dev/null || true
    done
    "$LSREGISTER" -f /Applications/MacRadio.app
    # La extensión del widget sigue corriendo con el binario viejo hasta que alguien la para; al
    # pararla, el sistema la vuelve a lanzar ya con el nuevo.
    pkill -f "MacRadio.app/Contents/PlugIns/MacRadioWidget.appex" 2>/dev/null || true
    open /Applications/MacRadio.app
    echo "✓ Instalada en /Applications"
fi
