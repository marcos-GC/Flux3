# FLUX Studio

App para Mac que usa la API de Black Forest Labs (FLUX 3) para generar y editar imágenes y vídeos.

## Instalar

### Opción rápida (recomendada)

Abre la app **Terminal**, pega esta línea y pulsa ↩:

```
curl -fsSL https://raw.githubusercontent.com/marcos-GC/Flux3/claude/flux-studio-macos-app-afvdnk/install.sh | bash
```

Descarga la última versión, la copia a **Aplicaciones** y la abre. Así macOS no muestra el aviso de seguridad. Para actualizar, vuelve a pegar la misma línea.

### Opción manual (con el instalador .dmg)

1. Descarga **FLUX-Studio.dmg** desde
   https://github.com/marcos-GC/Flux3/releases/download/ultima/FLUX-Studio.dmg
2. Ábrelo y arrastra **FLUX Studio** a la carpeta **Aplicaciones**.
3. La primera vez macOS la bloqueará, porque no está firmada con un certificado de pago de Apple. Para permitirla:
   **Ajustes del Sistema → Privacidad y seguridad**, baja hasta el final y pulsa **«Abrir igualmente»**.

## Primeros pasos

1. Abre **Ajustes** (rueda dentada, abajo a la izquierda).
2. Pega tu API key de Black Forest Labs (https://dashboard.bfl.ai → API Keys) y pulsa **Guardar en el Llavero**.
3. Pulsa **Probar conexión**. Debería mostrar tu saldo de créditos.
4. La primera vez que generes algo, macOS pedirá permiso para que FLUX Studio lea la clave del Llavero. Escribe **la contraseña de tu Mac** (no la API key) y pulsa **Permitir siempre**. Si pulsas solo «Permitir», volverá a preguntar en cada sesión.
   Tras instalar una versión nueva de la app, macOS lo pregunta una vez más: es normal, porque la app no está firmada con un certificado de pago de Apple.

## Dónde se guardan los archivos

Cada resultado se descarga en `~/Pictures/FLUX Studio/AAAA-MM-DD/` (en el Finder: Imágenes → FLUX Studio), junto con un `.json` que contiene el prompt, los parámetros, el identificador de la tarea y el coste. La carpeta se puede cambiar en Ajustes.

## Cambiar o borrar la API key

En **Ajustes**, pega la nueva clave y pulsa **Guardar en el Llavero**: sustituye a la anterior. **Borrar clave** la elimina. La clave se guarda solo en el Llavero de macOS (entrada «FLUX Studio · API key de BFL»), nunca en archivos ni en el código.

## Para desarrolladores

- Swift Package con dos módulos: `FluxCore` (cliente de la API, modelos y reglas, con tests) y `FluxStudio` (interfaz SwiftUI, macOS 14+).
- `swift build` y `swift test` compilan y prueban el proyecto.
- `./build_app.sh` monta `FLUX Studio.app` en `~/Applications`, y `./make_dmg.sh` crea `dist/FLUX-Studio.dmg`.
- GitHub Actions (`.github/workflows/build.yml`) compila, ejecuta los tests y comprueba que la app arranca en macOS en cada cambio. Cada cambio en la rama `claude/flux-studio-macos-app-afvdnk` publica además el `.dmg` en la release **ultima**.
