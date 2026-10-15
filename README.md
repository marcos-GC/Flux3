# FLUX Studio

App para Mac (macOS 14 o superior) que usa la API de Black Forest Labs (**FLUX 3**) para generar y editar imágenes y vídeos. Pensada para el estudio: se trabaja en una sola pantalla, con la imagen en grande, las herramientas a la izquierda y los resultados en una tira a la derecha.

## Instalar y actualizar

### Opción rápida (recomendada)

Abre la app **Terminal**, pega esta línea y pulsa ↩:

```
curl -fsSL https://raw.githubusercontent.com/marcos-GC/Flux3/claude/flux-studio-macos-app-afvdnk/install.sh | bash
```

Descarga la última versión, la copia a **Aplicaciones** y la abre, sin el aviso de seguridad de macOS. **Para actualizar, pega la misma línea otra vez.**

### Opción manual (instalador .dmg)

1. Descarga **FLUX-Studio.dmg**: https://github.com/marcos-GC/Flux3/releases/download/ultima/FLUX-Studio.dmg
2. Ábrelo y arrastra **FLUX Studio** a la carpeta **Aplicaciones**.
3. La primera vez macOS la bloqueará, porque no está firmada con un certificado de pago de Apple. Para permitirla:
   **Ajustes del Sistema → Privacidad y seguridad**, baja hasta el final y pulsa **«Abrir igualmente»**.

## Primeros pasos

1. Abre **Ajustes** (rueda dentada, abajo a la izquierda).
2. Pega tu API key de Black Forest Labs (https://dashboard.bfl.ai → API Keys) y pulsa **Guardar en el Llavero**.
3. Pulsa **Probar conexión**: debe mostrar tu saldo de créditos.
4. Elige la **región** (EU por defecto) y, si quieres, la carpeta de salida y los valores por defecto.
5. La primera vez que generes algo, macOS pedirá permiso para que FLUX Studio lea la clave del Llavero. Escribe **la contraseña de tu Mac** (no la API key) y pulsa **Permitir siempre**. Tras instalar una versión nueva, macOS lo pregunta una vez más: es normal.

## Cómo se usa: el Estudio

```
┌────────┬──────────────────────────────────────────┬────────┐
│ Nuevo  │                                          │ + Abrir│
│ Generar│                                          │        │
│ Editar │          IMAGEN SELECCIONADA             │  ▒▒▒   │ ← en curso
│ Borrar │          (en grande, proporción real)    │  img   │ ← seleccionada
│ Ampliar│                                          │  img   │
│ Deblur │   prompt · modelo   [Antes/Después] [Más]│  img   │
│ Probad.│                                          │   …    │
│ Vídeo  │  ┌────────────────────────────────────┐  │  TIRA  │
│        │  │ caja del prompt y sus opciones     │  │  DE    │
│ Histor.│  └────────────────────────────────────┘  │RESULT. │
│ Ajustes│        (fija en la parte inferior)       │        │
└────────┴──────────────────────────────────────────┴────────┘
```

- **Izquierda:** **Nuevo** (⌘N) empieza de cero: quita la imagen seleccionada, el prompt y las referencias (si hay algo escrito, pregunta antes). Debajo, las herramientas: todas trabajan sobre la **imagen seleccionada** y al cambiar de una a otra se conserva lo escrito. Con un vídeo seleccionado, las herramientas de imagen se desactivan y **Vídeo** se abre en el modo que encaja (imagen → Imagen a vídeo; vídeo → Continuar).
- **Centro:** la imagen seleccionada. Debajo, su prompt y los botones **Antes / Después** (compara con la imagen de la que sale), **Reutilizar**, **Como referencia**, **A vídeo**, **Finder** y **Más**.
- **Derecha:** la tira de resultados **de esta sesión**, con lo más nuevo arriba (lo anterior está en **Historial**). Un clic abre la imagen en grande. Lo que se está generando aparece como un hueco animado con su estado.
- **Encadenar:** si sigues en la imagen de la que sale un resultado, el resultado queda seleccionado, así que puedes generar → editar → borrar algo → ampliar sin salir de la pantalla.
- **Selección estable:** si mientras tanto has pasado a otra imagen, el resultado no te la cambia: aparece en la tira con la etiqueta **Nuevo** y un aviso arriba, **«Listo · Ver»**.
- **Generar con una imagen seleccionada:** al pulsar generar, la app pregunta qué hacer con ella: **Editar esta imagen** (el prompt describe el cambio), **Usarla como referencia** o **Crear una imagen nueva** (no se usa).

### Arrastrar imágenes desde el Finder

Al arrastrar una imagen sobre la pantalla aparecen dos zonas:

- **Editar esta imagen** (izquierda): se abre en grande y directamente en **Editar**.
- **Usar como referencia** (derecha): se añade a la caja de **Generar** como «image 1», «image 2»… (hasta 10).

### Herramientas

| Herramienta | Para qué | Qué haces |
|---|---|---|
| **Generar** | Imágenes nuevas con FLUX 3 Image | Prompt, referencias (hasta 10), proporción, resolución, 1–4 imágenes, tolerancia y «Consultar referencias en internet» en «Ajustes». ⌘↩ genera. |
| **Editar** | Cambios precisos (réplica de *Precise Editing* de BFL) | Escribe un cambio para toda la imagen o arrastra sobre ella para dibujar **regiones**, cada una con su instrucción, su imagen de referencia y su tipo (Editar, Nuevo, Mover, Proteger). «Ver prompt» enseña el texto exacto que se envía y deja editarlo. Zoom con ⌘ + rueda o pellizco; desplazamiento con espacio + arrastrar. |
| **Borrar** | Quitar objetos | Con **Marcar**, pinta en violeta lo que sobra y pulsa ↑. **Desmarcar** solo quita pintura violeta si te has pasado (no borra nada de la imagen). También: deshacer ⌘Z, invertir y limpiar. «Ampliar máscara» suaviza el borde. |
| **Ampliar** | Outpainting: extender la imagen | Elige la proporción del lienzo o los píxeles, arrastra la imagen dentro del lienzo y, si quieres, describe la zona nueva. |
| **Deblur** | Quitar desenfoque | Pulsa generar. |
| **Probador** | Vestir a una persona con una prenda | La persona es la imagen seleccionada; añade la prenda y descríbela en inglés. |
| **Vídeo** | FLUX 3 Video | Texto a vídeo, Imagen a vídeo (1–10 fotogramas clave, con segundos opcionales), Continuar, Editar y Escalar vídeo. **Borrador rápido** para probar barato y luego «Renderizar a calidad final» (antes de una hora). |

**Tolerancia de seguridad:** controla lo estricta que es la moderación de BFL (0 = muy estricto). No cambia el estilo. Va de 0 a 4 en FLUX 3 Image y Vídeo, y de 0 a 5 en Borrar, Ampliar, Deblur y Probador.

### Mejorar prompts con Claude (opcional)

En la caja de **Generar** y de **Vídeo** hay un botón **Mejorar** (⌘E). Envía tu idea a **Claude Haiku 5.5**, que la reescribe en inglés siguiendo las guías oficiales de prompting de FLUX 3 sin cambiar lo que pediste. Debajo explica en español qué ha cambiado, y con **↶** vuelves a tu texto.

Para usarlo, crea una API key en https://console.anthropic.com → API Keys y pégala en **Ajustes → Mejorar prompts con Claude → Guardar en el Llavero**. Pulsa **Probar** para comprobarla. Cada mejora cuesta décimas de céntimo.

## Dónde se guardan los archivos

Cada resultado se descarga nada más terminar (los enlaces de BFL caducan) en `~/Pictures/FLUX Studio/AAAA-MM-DD/` (en el Finder: **Imágenes → FLUX Studio**). Junto a cada imagen o vídeo hay un `.json` con el prompt, el prompt expandido por el modelo, los parámetros, el identificador de la tarea, el coste y la fecha. La carpeta se puede cambiar en **Ajustes**.

El **Historial** (barra lateral) muestra todo lo guardado, con búsqueda por prompt y filtro por modo. Desde ahí puedes abrir cualquier resultado en el Estudio, reutilizar sus parámetros o moverlo a la Papelera.

## Cambiar o borrar las API keys

En **Ajustes**, pega la nueva clave y pulsa **Guardar en el Llavero**: sustituye a la anterior. **Borrar clave** la elimina. Las claves (BFL y Anthropic) se guardan solo en el Llavero de macOS, en las entradas «FLUX Studio · API key de BFL» y «FLUX Studio · API key de Anthropic». Nunca se guardan en archivos ni en el código.

Si una clave queda expuesta (por ejemplo, en una captura), bórrala en dashboard.bfl.ai o console.anthropic.com, crea otra y guárdala de nuevo en Ajustes.

## Si algo falla

| Mensaje o síntoma | Qué hacer |
|---|---|
| «La API key no es válida» | Revisa la clave en Ajustes y pulsa «Probar conexión». |
| «No te quedan créditos» | Recarga en dashboard.bfl.ai. |
| «Moderado…» | Sube la tolerancia de seguridad (chip «Ajustes») o reformula el prompt. |
| «Límite de peticiones simultáneas» | Espera a que terminen otras peticiones; no se ha cobrado nada. |
| «BFL ha rechazado algún parámetro» | Mándale una captura a quien mantenga la app: la API cambia a menudo. |
| macOS pide la contraseña del Llavero | Escribe la contraseña del Mac y pulsa «Permitir siempre». |
| «No se puede abrir» al instalar con el .dmg | Ajustes del Sistema → Privacidad y seguridad → «Abrir igualmente», o instala con la línea de Terminal. |

## Para desarrolladores

- **Swift Package** con dos módulos:
  - `FluxCore`: cliente de la API (`BFLClient`, polling con timeout y cancelación), peticiones `Codable` de cada endpoint, construcción del prompt de Editar con precisión, máscara de Borrar, geometría de Outpainting, guardado e historial, y `PromptEnhancer` para Claude Haiku. Todo con tests.
  - `FluxStudio`: interfaz SwiftUI (MVVM sencillo, `async/await`).
- `swift build` y `swift test` compilan y prueban el proyecto.
- `./build_app.sh` monta `FLUX Studio.app` en `~/Applications`; `./make_dmg.sh` crea `dist/FLUX-Studio.dmg`.
- GitHub Actions (`.github/workflows/build.yml`) compila, ejecuta los tests y comprueba que la app del instalador arranca en macOS en cada cambio. Cada cambio en la rama `claude/flux-studio-macos-app-afvdnk` publica además el `.dmg` en la release **ultima**, que es la que descarga `install.sh`.

### Puntos de la API sin verificar en la documentación

La documentación de BFL no se pudo consultar desde el entorno de desarrollo. Se siguieron la especificación del proyecto y las guías oficiales de FLUX 3. Conviene revisar estos puntos si BFL devuelve errores de parámetro (422):

- Nombres de campos de Outpainting, Borrar, Deblur y Probador virtual (`vto-v2`).
- El campo del vídeo en `video-edit-v1` (`video`; el conector oficial lo llama `input_video`).
- La frase de una región con imagen de referencia en Editar con precisión. El texto del centro («in the centre of the frame») sí está verificado con la herramienta oficial.
