.pragma library

// Diccionario del widget. `en` es el idioma de publicación (mercado, README,
// capturas) y `es` el de uso diario; el idioma activo vive en
// ~/.config/looknfeel/lang y se cambia con el botoncito de la cabecera o con
// `looknfeel lang es`.
//
// Uso desde Panel.qml:  I18n.t("blur")  ·  I18n.t("backTo", { value: "12 px" })

var strings = {
    en: {
        // secciones
        headingOpacity: "OPACITY",
        headingSpacing: "SPACING AND BORDERS",
        headingEffects: "EFFECTS",
        // filas de sliders
        focused: "Focused window",
        unfocused: "Background windows",
        rounding: "Corner rounding",
        gapsIn: "Inner gaps",
        gapsOut: "Outer gaps",
        border: "Border width",
        // filas de interruptores
        blur: "Background blur",
        blurHint: "Blurs what you see behind translucent surfaces.",
        shadows: "Window shadows",
        shadowsHint: "A shadow around every window, to lift it off the background.",
        animations: "Animations",
        animationsHint: "Transitions for windows, workspaces and layers (bar, popups).",
        // resets
        resetOmarchy: "Back to Omarchy's value",
        resetOn: "Back to on",
        resetOff: "Back to off",
        backTo: "Back to {value}",
        resetAllHint: "Back to Omarchy's defaults (drops the block in looknfeel.lua)",
        // cabecera y tooltip
        tooltipBase: "Look'n'Feel · rounding {rounding}px · gaps {gapsIn}/{gapsOut}",
        tooltipBlur: " · blur",
        language: "Language",
        // fallos
        readFailed: "could not read Hyprland (exit {code})",
        failurePrefix: "No changes: "
    },
    es: {
        headingOpacity: "OPACIDAD",
        headingSpacing: "ESPACIADO Y BORDES",
        headingEffects: "EFECTOS",
        focused: "Ventana enfocada",
        unfocused: "Ventanas de fondo",
        rounding: "Redondeo de esquinas",
        gapsIn: "Gaps internos",
        gapsOut: "Gaps externos",
        border: "Grosor del borde",
        blur: "Desenfoque de fondo",
        blurHint: "Difumina lo que se ve detrás de las superficies translúcidas.",
        shadows: "Sombras de ventana",
        shadowsHint: "Sombra alrededor de cada ventana, para despegarla del fondo.",
        animations: "Animaciones",
        animationsHint: "Transiciones de ventanas, workspaces y capas (barra, popups).",
        resetOmarchy: "Volver al valor de Omarchy",
        resetOn: "Volver a activado",
        resetOff: "Volver a desactivado",
        backTo: "Volver a {value}",
        resetAllHint: "Volver a los valores de Omarchy (borra el bloque en looknfeel.lua)",
        tooltipBase: "Look'n'Feel · redondeo {rounding}px · gaps {gapsIn}/{gapsOut}",
        tooltipBlur: " · blur",
        language: "Idioma",
        readFailed: "no leí Hyprland (exit {code})",
        failurePrefix: "Sin cambios: "
    }
}

// t("blur") o t("backTo", { value: "12 px" }): los {nombre} se reemplazan.
function t(lang, key, subs) {
    var table = strings[lang] || strings.en
    var text = table[key]
    if (text === undefined) text = strings.en[key]
    if (text === undefined) return key
    if (subs) {
        for (var name in subs) {
            text = text.split("{" + name + "}").join(String(subs[name]))
        }
    }
    return text
}
