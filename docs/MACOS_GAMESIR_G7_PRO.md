# GameSir G7 Pro por Bluetooth en macOS

Notas del problema "el control está conectado pero el juego no lo detecta" en SoH 9.3.1 (Dewey Bravo) para macOS, con un GameSir G7 Pro (VID `0x3537`, PID `0x1022`, firmware 1.1.11).

## Síntomas

- macOS muestra **GameSir-G7 Pro – Connected** en Bluetooth.
- En **Settings → Controls → Popout Bindings Window → Link (P1)** solo aparecen **Keyboard** y **Mouse**.
- **Settings → Controls → Open Gamepad Mapper → Device** dice **No joysticks detected**.

## Causas encontradas

Eran tres problemas, uno detrás de otro:

1. **Permiso de Input Monitoring.** Por Bluetooth el control se anuncia como un dispositivo compuesto: control multimedia + gamepad + teclado + mouse. Como incluye un teclado, macOS no deja abrirlo sin el permiso **Privacy & Security → Input Monitoring**. Sin ese permiso, `IOHIDDeviceOpen` devuelve `kIOReturnNotPermitted` (`0xe00002e2`).
2. **SDL descarta el dispositivo.** SDL 2.32.10 (el que viene en `soh.app`) filtra en `src/joystick/darwin/SDL_iokitjoystick.c` por el *primary usage* del dispositivo. El G7 Pro reporta *Consumer Control* (`0x0C/0x01`) como primary usage, aunque su descriptor sí tiene una colección *Generic Desktop / Game Pad* (`0x01/0x05`). Por eso SDL lo ignora.
3. **SDL se lo cede a GameController.framework.** `[GCController supportsHIDDevice:]` devuelve `YES` para el control, pero el framework solo lo trata como teclado/mouse y nunca crea un `GCController`. SDL lo marca como "ya conocido" y nadie lo expone como joystick.

Lo que **no** funciona:

- **El receptor 2.4G.** Se presenta como USB clase `255/255/255` (protocolo XInput). macOS no trae driver para eso y el SDL de `soh.app` no está compilado con libusb.
- **Reinstalar o actualizar el juego.** El problema está en SDL, no en la versión de SoH.

## Solución

1. Activar **soh** en **System Settings → Privacy & Security → Input Monitoring**. Si macOS conserva una entrada vieja, se puede borrar con `tccutil reset ListenEvent com.shipofharkinian.ShipOfHarkinian` y volver a agregar la app con **+**.
2. Reemplazar el SDL de `soh.app` por uno parchado con [`scripts/macos/sdl2-iokit-composite-gamepad.patch`](../scripts/macos/sdl2-iokit-composite-gamepad.patch). El parche hace tres cosas:
   - Acepta dispositivos cuyo primary usage no es de joystick, siempre que `DeviceUsagePairs` incluya Joystick, Game Pad o Multi-axis.
   - En esos dispositivos solo lee los elementos dentro de la colección de gamepad, para que el teclado y el mouse no agreguen ejes ni botones.
   - Solo le cede a GameController.framework los dispositivos cuyo primary usage sí es de joystick.

   Para aplicarlo:

   ```sh
   scripts/macos/patch-sdl-composite-gamepad.sh /Applications/soh.app
   ```

   El script baja SDL 2.32.10, verifica el sha256, aplica el parche, compila para arm64 y x86_64 e instala la librería. La original queda respaldada como `libSDL2-2.0.0.dylib.original`.
3. Mapeo para el control por Bluetooth. Se guarda en `~/Library/Application Support/com.shipofharkinian.soh/usergamepadmappings.txt` y copia el layout del mapeo USB "GameSir G7 Pro" que ya trae `gamecontrollerdb.txt`, porque tiene los mismos 6 ejes, 16 botones y 1 cruceta:

   ```
   0300000037350000221000001b010000,GameSir G7 Pro (Bluetooth),a:b0,b:b1,x:b3,y:b4,back:b10,guide:b12,start:b11,leftstick:b13,rightstick:b14,leftshoulder:b6,rightshoulder:b7,dpup:h0.1,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,leftx:a0,lefty:a1,rightx:a2,righty:a3,lefttrigger:a5,righttrigger:a4,platform:Mac OS X,
   ```

   Si algún botón queda cambiado, se corrige desde **Settings → Controls → Open Gamepad Mapper → Map All → Save Mapping**.

## Notas

- Cambiar la librería rompe el sello de la firma ad-hoc de `soh.app` (`codesign --verify` muestra "a sealed resource is missing or invalid"). Si macOS se niega a abrir la app, hay que volver a firmarla con `codesign --force --deep -s - /Applications/soh.app` y después activar otra vez **soh** en Input Monitoring.
- Actualizar `soh.app` reemplaza el SDL parchado. Después de cada actualización hay que volver a correr el script.
- Para revertir: mover `libSDL2-2.0.0.dylib.original` de vuelta a `libSDL2-2.0.0.dylib` en `soh.app/Contents/Frameworks/`.
- La solución de fondo sería llevar este cambio a SDL (libsdl-org/SDL). Los builds oficiales de macOS usan el `libsdl2` de MacPorts (ver `.github/macports.yml`).
