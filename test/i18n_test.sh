#!/usr/bin/env bash
# El diccionario tiene que estar completo en los dos idiomas, el inglés tiene que
# ser el de fábrica y el panel no puede quedarse con textos de UI crudos: si algo
# no está en i18n.js, no se traduce.
# Corre en CI, sin Omarchy y sin Hyprland.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail=0
ok() { printf '\033[1;32m[ok]\033[0m   %s\n' "$1"; }
bad() {
    printf '\033[1;31m[fail]\033[0m %s\n' "$1" >&2
    fail=1
}

printf 'i18n (inglés y español)\n'

# 1) mismas claves en los dos idiomas
python3 - <<'PY' && ok "en y es tienen las mismas claves" || bad "faltan claves en algún idioma"
import re, sys, pathlib
src = pathlib.Path("i18n.js").read_text()
blocks = {}
for lang in ("en", "es"):
    m = re.search(rf"\n    {lang}: \{{(.*?)\n    \}}", src, re.S)
    if not m:
        print(f"no encontré el bloque de {lang}", file=sys.stderr); sys.exit(1)
    blocks[lang] = set(re.findall(r"^\s*([a-zA-Z][A-Za-z0-9_]*):", m.group(1), re.M))
missing_en = blocks["es"] - blocks["en"]
missing_es = blocks["en"] - blocks["es"]
if missing_en or missing_es:
    print("faltan en en:", sorted(missing_en), "| en es:", sorted(missing_es), file=sys.stderr)
    sys.exit(1)
print(f"{len(blocks['en'])} claves")
PY

# 2) el idioma por defecto es inglés (mercado) y se cambia con un botón, no un dropdown
grep -q 'import "i18n.js" as I18n' Panel.qml && ok "el panel usa el diccionario" || bad "Panel.qml no importa i18n.js"
grep -q 'lang: "en"' Panel.qml && ok "el idioma por defecto es inglés" || bad "el idioma por defecto no es inglés"
grep -qE 'onClicked: root\.toggleLang\(\)' Panel.qml && ok "hay un botón para alternar (no dropdown)" || bad "no hay botón que alterne el idioma"
grep -q 'iconText: root.lang.toUpperCase()' Panel.qml && ok "el botón muestra el idioma activo" || bad "el botón no muestra el idioma activo"

# 3) el CLI expone el idioma y lo guarda donde lo lee el panel
grep -qE '^lang_cmd\(\)' bin/looknfeel && ok "el CLI expone 'lang'" || bad "el CLI no expone 'lang'"
grep -q 'config/looknfeel/lang' bin/looknfeel || bad "el CLI no guarda el idioma en ~/.config/looknfeel/lang"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# HOME propio para no tocar la config real (el idioma vive en $HOME/.config).
looknfeel_lang() { env -u XDG_CONFIG_HOME HOME="$tmp" bin/looknfeel "$@"; }

if [[ $(looknfeel_lang lang) == en ]]; then
    ok "sin archivo de idioma, el default es en"
else
    bad "el default del CLI no es en"
fi
looknfeel_lang lang es >/dev/null
if [[ $(cat "$tmp/.config/looknfeel/lang") == es ]]; then
    ok "el CLI escribe el idioma en ~/.config/looknfeel/lang"
else
    bad "el CLI no escribió el idioma"
fi
if [[ $(looknfeel_lang lang) == es ]]; then
    ok "el CLI lo relee"
else
    bad "el CLI no relee el idioma"
fi
# Lo que lee una persona sale en el idioma activo (acá, el recién elegido).
if looknfeel_lang lang es | grep -q 'Idioma del widget: es'; then
    ok "la salida del CLI respeta el idioma activo"
else
    bad "la salida del CLI no respeta el idioma activo"
fi

# 4) nada de textos de UI crudos en español fuera del diccionario
hits=$(grep -nE '(label|text|heading|hint|description|tooltipText)[A-Za-z]*: *"[^"]*(Ventana|Redondeo|Gaps|Grosor|Sombras|Animaciones|Volver|Sin cambios|Difumina|Sombra|Idioma|OPACIDAD|EFECTOS)' Panel.qml || true)
if [[ -n $hits ]]; then
    bad "quedaron textos sin traducir en Panel.qml"
    printf '%s\n' "$hits" | sed 's/^/       /' >&2
else
    ok "no quedan textos de UI sin pasar por el diccionario"
fi

if ((fail)); then
    printf '\033[1;31mi18n: hay fallos\033[0m\n' >&2
    exit 1
fi
printf '\033[1;32mi18n: todo bien\033[0m\n'
