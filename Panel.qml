import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

// Look'n'Feel — afiná el look'n'feel de Hyprland desde la barra.
//
// El panel es data-driven: `looknfeel read` devuelve los valores vivos
// MÁS la metadata de cada opción (tipo, ruta Lua, default de Omarchy) y las
// filas salen de dos modelos — `sliderRows` y `effectRows` — con tres Repeaters.
// Agregar un control es agregar un renglón: no hay una copia de la misma fila
// por cada opción.
//
// Aplicar en vivo va por el socket IPC de Hyprland (Quickshell.Io.Socket), sin
// procesos de por medio. Hyprland cierra la conexión después de cada comando,
// así que el canal se reconecta por comando y siempre viaja el último valor
// pedido (no una cola): eso es lo que hace que arrastrar se sienta continuo.
// Persistir sigue siendo el CLI, que conoce los defaults y el orden del bloque
// gestionado en ~/.config/hypr/looknfeel.lua.
Panel {
  id: root
  moduleName: "meperdonas.looknfeel"
  ipcTarget: "meperdonas.looknfeel"

  // El CLI viaja dentro del plugin y se resuelve por la ruta de ESTE archivo, no
  // por el nombre de la carpeta: anda igual si lo clonás con `omarchy plugin
  // add` (que lo deja en una carpeta con el id) o si le cambiás el id.
  readonly property string bundledCli: decodeURIComponent(String(Qt.resolvedUrl("bin/looknfeel")).replace(/^file:\/\//, ""))
  readonly property string configuredCli: setting("command", "")
  readonly property string cli: configuredCli !== "" ? configuredCli : bundledCli
  // Icono propio del widget (glifo Nerd Font en pares subrogados: los glifos
  // viven en el plano 15 de la PUA). Por defecto md-tune (U+F062E).
  readonly property string glyph: setting("icon", "\udb81\ude2e")
  readonly property string resetGlyph: "\udb80\udc6f"  // md-backup_restore (U+F006F)
  // Click de UI: switches, resets y al soltar un slider. Se apaga con el ajuste
  // `sound` (y con eso ni se carga el efecto).
  readonly property bool soundEnabled: setting("sound", true)

  readonly property color rowForeground: bar ? bar.foreground : "white"
  readonly property string rowFont: bar ? bar.fontFamily : "monospace"

  // Lo llena `read`: `values` son los valores vivos y `optionMeta` trae por
  // clave el tipo, la ruta Lua y el default de Omarchy.
  property var values: ({})
  property var optionMeta: ({})
  property bool loaded: false
  property string failure: ""

  // Canal vivo (ver pumpLive).
  property bool liveBusy: false
  property bool liveFailed: false
  property string pendingLua: ""
  property string fallbackKey: ""
  property real fallbackValue: 0
  // Último valor previsualizado sin persistir: si el panel se cierra en medio de
  // un arrastre, se persiste igual al cerrar (si no, la sesión queda con un
  // valor que el archivo de config no conoce).
  property var dirtyPreview: null

  // ------------------------------------------------------------- los modelos
  // `heading` abre una sección (separador + título) antes de esa fila.
  readonly property var sliderRows: [
    { heading: "OPACIDAD", key: "focused", label: "Ventana enfocada", min: 10, max: 100, unit: "%", scale: 100 },
    { key: "unfocused", label: "Ventanas de fondo", min: 10, max: 100, unit: "%", scale: 100 },
    { heading: "ESPACIADO Y BORDES", key: "rounding", label: "Redondeo de esquinas", min: 0, max: 40, unit: "px" },
    { key: "gapsIn", label: "Gaps internos", min: 0, max: 60, unit: "px" },
    { key: "gapsOut", label: "Gaps externos", min: 0, max: 60, unit: "px" },
    { key: "border", label: "Grosor del borde", min: 0, max: 10, unit: "px" }
  ]

  readonly property var effectRows: [
    {
      heading: "EFECTOS", key: "blur", label: "Background blur",
      hint: "Difumina lo que se ve detrás de las superficies translúcidas."
    },
    {
      key: "shadows", label: "Sombras de ventana",
      hint: "Sombra alrededor de cada ventana, para despegarla del fondo."
    },
    {
      key: "animations", label: "Animaciones",
      hint: "Transiciones de ventanas, workspaces y capas (barra, popups)."
    }
  ]

  // True cuando algún valor vivo difiere del default de Omarchy: es el estado
  // que habilita el reset global de la cabecera.
  readonly property bool commandsDirty: {
    for (var key in optionMeta) if (!isDefault(key)) return true
    return false
  }

  implicitWidth: 30
  implicitHeight: bar ? bar.barSize : 26

  // ------------------------------------------------------------- utilidades
  function shq(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }
  function call(args) {
    if (bar) bar.run(shq(cli) + " " + args)
  }
  function literal(value) {
    return value === true ? "true" : value === false ? "false" : String(value)
  }
  function refresh() {
    if (!readProc.running) readProc.running = true
  }
  function numberValue(key) {
    var current = values[key]
    return current === undefined || current === null ? 0 : Number(current)
  }
  function rowScale(row) {
    return row.scale === undefined ? 1 : row.scale
  }
  // Lo que muestra el slider: la unidad cruda de Hyprland escalada a la unidad
  // de la fila (0.95 de opacidad → 95 %).
  function shownValue(row) {
    return Math.round(numberValue(row.key) * rowScale(row))
  }
  function defaultValue(key) {
    var meta = optionMeta[key]
    return meta === undefined ? undefined : meta.default
  }
  function isDefault(key) {
    var fallback = defaultValue(key)
    return fallback === undefined || values[key] === fallback
  }
  function defaultLabel(key, unit) {
    var fallback = defaultValue(key)
    if (fallback === undefined) return "Volver al valor de Omarchy"
    if (fallback === true) return "Volver a activado"
    if (fallback === false) return "Volver a desactivado"
    var shown = Math.round(Number(fallback) * (unit === "%" ? 100 : 1))
    return "Volver a " + shown + (unit === "%" ? " %" : " " + unit)
  }
  function tooltipText() {
    if (!loaded) return "Look'n'Feel"
    return "Look'n'Feel · redondeo " + Math.round(numberValue("rounding")) + "px · gaps "
      + Math.round(numberValue("gapsIn")) + "/" + Math.round(numberValue("gapsOut"))
      + (values.blur ? " · blur" : "")
  }

  // ------------------------------------------------ aplicar (vivo / persistir)
  // Arma el mismo `hl.config({...})` anidado que escribe el CLI, a partir de la
  // ruta Lua que manda la metadata ("decoration.blur.enabled" → tablas anidadas).
  function luaCall(path, value) {
    var parts = String(path).split(".")
    var out = literal(value)
    for (var i = parts.length - 1; i >= 0; i--) out = "{ " + parts[i] + " = " + out + " }"
    return "hl.config(" + out + ")"
  }

  function preview(key, value) {
    var meta = optionMeta[key]
    if (!meta) return
    dirtyPreview = { key: key, value: value }
    if (liveFailed) {
      // Sin socket (o sin firma de Hyprland en el entorno) se cae al CLI, que
      // arranca un proceso por cambio; se limita a ~20 por segundo.
      fallbackKey = key
      fallbackValue = value
      if (!fallbackTimer.running) fallbackTimer.start()
      return
    }
    pendingLua = luaCall(meta.lua, value)
    pumpLive()
  }

  function pumpLive() {
    if (liveBusy || pendingLua === "") return
    if (!hyprSocket.connected) {
      hyprSocket.connected = true
      return
    }
    var code = pendingLua
    pendingLua = ""
    liveBusy = true
    liveWatchdog.restart()
    hyprSocket.write(code + "\n")
    hyprSocket.flush()
  }

  // Persiste + aplica por el CLI: un proceso por soltada, no por píxel.
  function commit(key, value) {
    if (dirtyPreview && dirtyPreview.key === key) dirtyPreview = null
    var next = {}
    for (var k in values) next[k] = values[k]
    next[key] = value
    values = next
    call("set " + key + " " + literal(value))
  }

  function click() {
    var effect = sound.item
    if (effect) effect.play()
  }

  function resetItem(key) {
    var fallback = defaultValue(key)
    if (fallback === undefined) return
    click()
    commit(key, fallback)
  }

  function resetAll() {
    click()
    dirtyPreview = null
    pendingLua = ""
    call("reset")
    rereadTimer.restart()
  }

  function toggleEffect(key) {
    click()
    commit(key, values[key] !== true)
  }

  Component.onCompleted: refresh()
  onOpenedChanged: {
    if (opened) {
      refresh()
    } else if (dirtyPreview) {
      // Arrastre que quedó a medio camino: se persiste al cerrar.
      commit(dirtyPreview.key, dirtyPreview.value)
    }
  }

  // Click de UI (switches, resets y suelta de slider). Cargado aparte: si el
  // shell no tuviera QtMultimedia se pierde el sonido, no el panel.
  Loader {
    id: sound
    active: root.soundEnabled
    source: "assets/Sound.qml"
    onStatusChanged: if (status === Loader.Error) console.log("looknfeel: sin sonido, QtMultimedia no está disponible")
  }

  Process {
    id: readProc
    command: ["/bin/bash", "-lc", root.cli + " read"]
    stdout: StdioCollector { id: readOutput }
    onExited: function (exitCode) {
      var data = null
      try { data = JSON.parse(String(readOutput.text || "")) } catch (error) { data = null }
      if (!data || data.ok !== true) {
        root.failure = data && data.error ? data.error : "no leí Hyprland (exit " + exitCode + ")"
        return
      }
      root.failure = ""
      root.loaded = true
      root.values = data.values
      root.optionMeta = data.options || ({})
      if (!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")) root.liveFailed = true
    }
  }

  // ------------------------------------------------------------- canal vivo
  readonly property string hyprSocketPath: Quickshell.env("XDG_RUNTIME_DIR") + "/hypr/"
    + Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") + "/.socket.sock"

  Socket {
    id: hyprSocket
    path: root.hyprSocketPath
    connected: false
    parser: SplitParser {
      // La respuesta ("ok") marca el fin del comando en vuelo.
      onRead: function (line) {
        root.liveBusy = false
        root.pumpLive()
      }
    }
    onConnectionStateChanged: {
      if (!hyprSocket.connected) root.liveBusy = false
      root.pumpLive()
    }
    onError: function (error) {
      root.liveFailed = true
    }
  }

  // Red de seguridad: si una respuesta se pierde, el canal no queda trabado.
  Timer {
    id: liveWatchdog
    interval: 250
    repeat: false
    onTriggered: {
      root.liveBusy = false
      root.pumpLive()
    }
  }

  // Sólo se usa cuando el socket no está disponible.
  Timer {
    id: fallbackTimer
    interval: 50
    repeat: false
    onTriggered: root.call("live " + root.fallbackKey + " " + root.literal(root.fallbackValue))
  }

  // Tras un reset el CLI toca nueve opciones: le damos un respiro antes de releer.
  Timer {
    id: rereadTimer
    interval: 500
    repeat: false
    onTriggered: root.refresh()
  }

  // ---------------------------------------------------------------- la barra
  Rectangle {
    id: iconButton
    anchors.fill: parent
    radius: height / 2
    // El pill queda prendido mientras el panel está abierto: se ve de un vistazo
    // de qué widget es el popup que tenés delante.
    color: mouse.containsMouse || root.opened ? Qt.rgba(1, 1, 1, 0.10) : "transparent"

    Text {
      id: barGlyph
      anchors.centerIn: parent
      text: root.glyph
      color: root.rowForeground
      font.family: root.rowFont
      font.pixelSize: 16
      opacity: root.opened || mouse.containsMouse ? 1.0 : 0.92
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        root.toggle()
        if (root.opened) root.refresh()
      }
      onEntered: if (bar) bar.showTooltip(mouse, root.tooltipText())
      onExited: if (bar) bar.hideTooltip(mouse)
    }
  }

  // ---------------------------------------------------------------- el panel
  PopupCard {
    id: popup
    anchorItem: iconButton
    bar: root.bar
    owner: root
    open: root.opened
    // Ancho del panel y aire entre el borde y el contenido: las filas derivan
    // los dos de acá (ancho y margen superior), así que mover estos números
    // reacomoda todo el panel sin tocar las filas.
    contentWidth: 360
    padding: 20
    // El alto sale del contenido real, pero el contenido NO puede estirarse al
    // popup (`anchors.fill`): ese círculo hace que Qt no llegue a pintar la
    // ventana. Ancho fijo, alto del contenido.
    contentHeight: popup.fittedContentHeight(content.implicitHeight + popup.padding * 2)

    Column {
      id: content
      width: popup.contentWidth - popup.padding * 2
      anchors.top: parent.top
      anchors.topMargin: popup.padding
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 12

      // Cabecera: icono + nombre + reset global. Los resets por ítem viven en
      // cada fila.
      Item {
        width: parent.width
        implicitHeight: Math.max(headerTitle.implicitHeight, headerReset.implicitHeight)

        Text {
          id: headerGlyph
          text: root.glyph
          color: root.rowForeground
          font.family: root.rowFont
          font.pixelSize: 18
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          id: headerTitle
          textFormat: Text.PlainText
          text: "Look'n'Feel"
          color: root.rowForeground
          font.family: root.rowFont
          font.pixelSize: 15
          font.bold: true
          anchors.left: headerGlyph.right
          anchors.leftMargin: 9
          anchors.verticalCenter: parent.verticalCenter
        }

        PanelActionButton {
          id: headerReset
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          iconText: root.resetGlyph
          tooltipText: "Volver a los valores de Omarchy (borra el bloque en looknfeel.lua)"
          foreground: root.rowForeground
          fontFamily: root.rowFont
          enabled: root.loaded && root.commandsDirty
          opacity: enabled ? 1 : 0.3
          onClicked: root.resetAll()
        }
      }

      // Una fila por opción: título + valor + reset propio, slider abajo.
      Repeater {
        model: root.sliderRows

        delegate: Column {
          id: sliderRow
          required property var modelData

          width: parent ? parent.width : 0
          spacing: 4

          PanelSeparator {
            visible: !!sliderRow.modelData.heading
            foreground: root.rowForeground
            width: parent.width
          }

          PanelSectionHeader {
            visible: !!sliderRow.modelData.heading
            text: sliderRow.modelData.heading || ""
            foreground: root.rowForeground
            fontFamily: root.rowFont
          }

          Item {
            width: parent.width
            implicitHeight: Math.max(rowLabel.implicitHeight, rowReset.implicitHeight)

            Text {
              id: rowLabel
              textFormat: Text.PlainText
              text: sliderRow.modelData.label
              color: root.rowForeground
              font.family: root.rowFont
              font.pixelSize: 13
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            PanelActionButton {
              id: rowReset
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: root.resetGlyph
              tooltipText: root.defaultLabel(sliderRow.modelData.key, sliderRow.modelData.unit)
              foreground: root.rowForeground
              fontFamily: root.rowFont
              fontSize: 13
              size: 18
              enabled: root.loaded && !root.isDefault(sliderRow.modelData.key)
              opacity: enabled ? 1 : 0.3
              onClicked: root.resetItem(sliderRow.modelData.key)
            }

            Text {
              id: rowValue
              textFormat: Text.PlainText
              text: Math.round(rowSlider.dragging ? rowSlider.liveValue : root.shownValue(sliderRow.modelData))
                + sliderRow.modelData.unit
              color: Qt.darker(root.rowForeground, 1.4)
              font.family: root.rowFont
              font.pixelSize: 12
              font.bold: true
              anchors.right: rowReset.left
              anchors.rightMargin: 8
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          PanelSlider {
            id: rowSlider
            width: parent.width
            bar: root.bar
            minimum: sliderRow.modelData.min
            maximum: sliderRow.modelData.max
            step: 1
            integer: true
            value: root.shownValue(sliderRow.modelData)
            onMoved: function (v) {
              root.preview(sliderRow.modelData.key, v / root.rowScale(sliderRow.modelData))
            }
            onReleased: function (v) {
              root.click()
              root.commit(sliderRow.modelData.key, v / root.rowScale(sliderRow.modelData))
            }
          }
        }
      }

      // Una fila por interruptor, con su descripción y su reset propio.
      Repeater {
        model: root.effectRows

        delegate: Column {
          id: effectRow
          required property var modelData

          width: parent ? parent.width : 0
          spacing: 6

          PanelSeparator {
            visible: !!effectRow.modelData.heading
            foreground: root.rowForeground
            width: parent.width
          }

          PanelSectionHeader {
            visible: !!effectRow.modelData.heading
            text: effectRow.modelData.heading || ""
            foreground: root.rowForeground
            fontFamily: root.rowFont
          }

          Item {
            width: parent.width
            implicitHeight: effectToggle.implicitHeight

            Toggle {
              id: effectToggle
              width: parent.width - effectReset.width - 8
              anchors.left: parent.left
              anchors.top: parent.top
              label: effectRow.modelData.label
              description: effectRow.modelData.hint
              checked: root.values[effectRow.modelData.key] === true
              foreground: root.rowForeground
              fontFamily: root.rowFont
              onClicked: root.toggleEffect(effectRow.modelData.key)
            }

            PanelActionButton {
              id: effectReset
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.topMargin: 6
              iconText: root.resetGlyph
              tooltipText: root.defaultLabel(effectRow.modelData.key, "")
              foreground: root.rowForeground
              fontFamily: root.rowFont
              enabled: root.loaded && !root.isDefault(effectRow.modelData.key)
              opacity: enabled ? 1 : 0.3
              onClicked: root.resetItem(effectRow.modelData.key)
            }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: root.failure !== ""
        width: parent.width
        text: root.failure === "" ? "" : "Sin cambios: " + root.failure
        color: root.bar ? root.bar.urgent : "#E05561"
        font.family: root.rowFont
        font.pixelSize: 11
        wrapMode: Text.WordWrap
      }
    }
  }
}
