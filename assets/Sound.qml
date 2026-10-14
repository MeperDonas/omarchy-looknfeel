import QtQuick
import QtMultimedia

// Click de UI. Vive en su propio archivo y se carga con un Loader desde
// Panel.qml: si el shell no tuviera QtMultimedia, se pierde el sonido pero el
// panel sigue andando mudo (en vez de no cargar el widget entero).
//
// El WAV viaja dentro del plugin (click.wav, 22 ms): no depende del tema de
// sonidos del sistema, que no trae ningún sample de click.
SoundEffect {
  id: click

  source: "click.wav"
  volume: 0.40
}
