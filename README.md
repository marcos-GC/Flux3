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
│ Deblur │              prompt · modelo             │  img   │
│ Probad.│                                          │   …    │
│ Vídeo  │  ┌────────────────────────────────────┐  │  TIRA  │
│        │  │ caja del prompt y sus opciones     │  │  DE    │
│ Histor.│  └────────────────────────────────────┘  │RESULT. │
│ Ajustes│        (fija en la parte inferior)       │        │
└────────┴──────────────────────────────────────────┴────────┘
```

- **Izquierda:** **Nuevo** (⌘N) empieza de cero: quita la imagen seleccionada, el prompt y las referencias (si hay algo escrito, pregunta antes). Debajo, las herramientas: todas trabajan sobre la **imagen seleccionada** y al cambiar de una a otra se conserva lo escrito. Con un vídeo seleccionado, las herramientas de imagen se desactivan y **Vídeo** se abre en el modo que encaja (imagen → Imagen a vídeo; vídeo → Continuar).
- **Centro:** la imagen seleccionada, con su prompt debajo. Encima de la caja de cada herramienta hay una **barra de iconos**, igual en todas las pantallas (al pasar el ratón se ve qué hace cada uno): **Original**, **Antes / Después** (compara con la imagen de la que sale), **Reutilizar**, **Como referencia**, **A vídeo**, **Enviar al asistente**, **Finder** y **Más**; con un vídeo, **Continuar**, **Editar** y **Escalar**. El **zoom** y **Recortar** están en horizontal arriba a la derecha.
- **Derecha:** la tira con **todo lo que has generado**, también en días y sesiones anteriores, con lo más nuevo arriba y separado por días (Hoy, Ayer, fecha). No se vacía al pulsar **Nuevo**. Un clic abre la imagen en grande. Lo que se está generando aparece como un hueco animado con su estado.
- **Encadenar:** si sigues en la imagen de la que sale un resultado, el resultado queda seleccionado, así que puedes generar → editar → borrar algo → ampliar sin salir de la pantalla.
- **Trabajar sin esperar:** mientras algo se genera puedes pulsar **Nuevo** (⌘N), abrir otra imagen, cambiar de herramienta o lanzar otra petición (también en Editar, Borrar, Ampliar…). Lo que estaba en marcha sigue por detrás y aparece en la tira al terminar.
- **Volver al original:** después de editar, el botón **Original** (⌘↑) vuelve a la imagen de antes de editar, sin buscarla. Está en la barra de Editar y bajo la imagen en las demás herramientas. Las ediciones siguen en la tira.
- **Copiar y pegar:** ⌘C copia la imagen seleccionada (el archivo y la imagen). ⌘V pega una imagen copiada aquí, en el Finder o en otra app (también capturas) y pregunta si quieres **editarla** o **usarla como referencia**. Las que no tienen archivo se guardan en «Pegadas», dentro de la carpeta de salida. Si estás escribiendo y has copiado texto, ⌘V pega el texto como siempre.
- **Antes / Después en todas las pantallas:** debajo de la imagen (Generar, Borrar, Rellenar, Ampliar, Deblur, Probador), en la barra de Editar y en la barra de Collage (foto base frente al collage). Si la imagen no sale de otra, el botón aparece desactivado.
- **Zoom y recorte en todas las pantallas:** arriba a la derecha, en horizontal (también en Borrar, Rellenar y Ampliar, sobre el lienzo de pintar o ampliar), y en las barras de Editar y Collage, están **− / + / Ajustar** y **Recortar**. En Borrar y Rellenar el zoom ayuda a pintar la máscara con precisión; en Ampliar se recorta la imagen de partida, no el lienzo ampliado. Zoom con ⌘ + rueda o pellizco; con zoom, dos dedos (o arrastrar, en Generar) desplazan la imagen. Al recortar, mueve el recuadro o sus esquinas, elige proporción si quieres (Libre, 1:1, 4:5, 16:9…) y pulsa **✓** (↩) o **✕** (Esc). El recorte se guarda como imagen nueva en la tira, con **Antes / Después** frente a la original, que no cambia. En Collage se recorta el collage aplanado.
- **Comparar dos fotos:** ⌘-clic en una miniatura de la tira (o clic derecho → «Comparar con la imagen en grande») la compara con la que tienes en grande, con la cortinilla. «Intercambiar» cambia los lados y **Esc** termina. En Editar, **Antes / Después** compara cada edición con la imagen de la que sale.
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
| **Editar** | Cambios precisos (réplica de *Precise Editing* de BFL) | Escribe un cambio para toda la imagen o arrastra sobre ella para dibujar **regiones**, cada una con su instrucción, su imagen de referencia y su tipo (Editar, Nuevo, Mover, Proteger). En **Resolución** está también **Como la original** (`match_input`): la edición sale del mismo tamaño que la foto, hasta 4 MP. «Ver prompt» enseña el texto exacto que se envía y deja editarlo. La barra de encima solo lleva iconos (al pasar el ratón se ve qué hace cada uno). Zoom con ⌘ + rueda o pellizco; desplazamiento con espacio + arrastrar. |
| **Rellenar** | *Pintar y rellenar*: inpainting con máscara | Pinta con el **pincel** la zona que quieres cambiar, o márcala con el **polígono** (clic en cada esquina, clic en el primer punto para cerrar) para formas exactas como el tablero de una mesa. Describe qué poner (mejor en inglés) y, si quieres, añade una imagen de **referencia**. Solo cambia lo marcado. |
| **Borrar** | Quitar objetos | Con **Marcar**, pinta en violeta lo que sobra y pulsa ↑. **Desmarcar** solo quita pintura violeta si te has pasado (no borra nada de la imagen). También: deshacer ⌘Z, invertir y limpiar. «Ampliar máscara» suaviza el borde. |
| **Ampliar** | Outpainting: extender la imagen | Elige la proporción del lienzo o los píxeles, arrastra la imagen dentro del lienzo y, si quieres, describe la zona nueva. |
| **Deblur** | Quitar desenfoque | Pulsa generar. |
| **Probador** | Vestir a una persona con una prenda | La persona es la imagen seleccionada; añade la prenda y descríbela en inglés. |
| **Vídeo** | FLUX 3 Video | Texto a vídeo, Imagen a vídeo (1–10 fotogramas clave, con segundos opcionales), Continuar, Editar y Escalar vídeo. **Borrador rápido** para probar barato y luego «Renderizar a calidad final» (antes de una hora). |

**Tolerancia de seguridad:** controla lo estricta que es la moderación de BFL (0 = muy estricto). No cambia el estilo. Va de 0 a 4 en FLUX 3 Image y Vídeo, y de 0 a 5 en Borrar, Ampliar, Deblur y Probador.

### Pintar y rellenar (inpainting con máscara)

FLUX 3 Image no acepta máscara, así que la app hace lo mismo que un flujo de inpainting de ComfyUI en dos pasos:

1. Envía la foto entera a FLUX 3 Image con un prompt de edición que señala la caja de la zona marcada (el mismo formato que **Editar**; «Ver prompt» lo enseña).
2. Del resultado **solo pega lo que hay dentro de la zona marcada** sobre tu foto original, con el borde suavizado. Lo de fuera queda idéntico, píxel a píxel, y a la resolución original.

- **Pincel** o **Polígono** (icono del pentágono). Con el polígono, cada clic es una esquina unida a la anterior con una línea recta; clic en el primer punto (o «Cerrar forma») para cerrarla, **Esc** para descartarla y ⌘Z quita la última esquina. «Desmarcar» con el polígono recorta lo marcado (por ejemplo, el hueco de un jarrón sobre la mesa). Pincel y polígono se pueden combinar. También están en **Borrar**.
- **Ajustes:** resolución, tolerancia, formato, **Ampliar zona** y **Suavizar borde** (por defecto 6 y 12 px para una foto de unos 2000 px; se ajustan al tamaño real). Para un cambio de material con bordes nítidos (una mesa), baja ambos a 0–4 px; si se nota la costura, súbelos. **Pegar solo en la zona pintada** se puede desactivar para guardar la imagen entera de FLUX.
- Cuesta lo mismo que una edición de FLUX 3 Image (FLUX genera la imagen entera aunque solo se use una parte).

### Copiar prompts y «Prompts guardados»

- **Copiar y pegar prompt y parámetros:** clic derecho en una foto → **«Copiar prompt y parámetros»** (o **⌥⌘C** con la foto en grande). Luego, en la herramienta donde estés (Generar, Editar, Collage, Ampliar, Vídeo), **⌥⌘V** o clic derecho → «Pegar prompt y parámetros» pone el texto y los ajustes (resolución, proporción, tolerancia…). El texto también queda en el portapapeles para pegarlo con ⌘V donde quieras.
- **Prompts guardados** (barra lateral, icono de libros): tu biblioteca de prompts que han funcionado, con **título**, **explicación**, el prompt, sus parámetros y una miniatura. Se guardan con clic derecho en una foto → **«Guardar en Prompts guardados…»**, con el botón de libros junto a la caja del prompt («Guardar este prompt…») o con **⌥⌘S**. Desde la biblioteca: **Usar** (lo pone en la herramienta abierta), Copiar, Editar y Borrar, con buscador. El botón de libros también da acceso rápido a los últimos.
- Se guardan en «Prompts guardados», dentro de la carpeta de salida.

### Collage (montaje + «Hacer realista»)

Una capa propia de la app, por encima de FLUX: un pequeño Photoshop para montar escenas y que FLUX las convierta en una foto realista.

1. **Base:** elige una foto (por ejemplo, la librería del salón). Si tenías una imagen seleccionada, se usa como base al abrir Collage.
2. **Objetos:** añádelos con el botón **Añadir objetos** (icono de foto con +) de la barra, arrastrándolos desde el Finder o la tira, con **⌘V** o con clic derecho → «Añadir al collage». Sirven PNG recortados o fotos normales: **Quitar fondo** detecta el objeto con el recorte de sujetos de macOS (gratis, sin internet) sin borrar nada de la foto: luego puedes **agrandar o encoger el borde** (si se ha comido parte del objeto o quedan restos de fondo), **suavizarlo**, recuperar o borrar zonas concretas con **Recuperar (R)** y **Goma (E)**, **ajustar la caja al objeto** o **quitar el recorte** para volver a la foto entera.
3. **Transformar:** arrastra para mover (⇧ = recto) · **esquinas** = escalar sin deformar · **⌘ + esquina** = perspectiva · **lados** = más ancho, estrecho, alto o bajo · **círculo de arriba** = girar (⇧ = de 15 en 15°) · flechas = mover un poco.
4. **Capas:** panel a la derecha (arriba = delante): ocultar, opacidad, voltear, delante/detrás, duplicar (⌘D), quitar transformaciones y borrar (⌫). **⌘Z / ⇧⌘Z** deshacen y rehacen.
5. **Goma:** con una capa seleccionada, **Goma** (E) borra partes pintando encima y **Recuperar** (R) las vuelve a pintar; **[** y **]** cambian el tamaño del pincel y **V** o **Esc** vuelven a mover. Funciona aunque la capa esté girada o en perspectiva, y ⌘Z lo deshace.
6. **Se guarda solo:** cada collage se guarda automáticamente en «Collages/Proyectos» (dentro de la carpeta de salida). El menú del proyecto (icono de capas, a la izquierda de la barra; su nombre sale al pasar el ratón) permite renombrarlo, abrir otro o empezar uno nuevo; al entrar en Collage sin nada abierto aparecen los últimos para seguir con ellos.
7. **Hacer realista** (⌘↩): junta el collage (se guarda en «Collages», dentro de la carpeta de salida) y lo envía a FLUX 3 Image con instrucciones para mantener la composición e integrar luz, sombras y bordes. Con **Enviar fotos originales**, también van las fotos de cada objeto (hasta 9) para que respete mejor cómo son. Puedes añadir indicaciones propias y usar **Mejorar**. El resultado aparece en la tira con **Antes / Después** frente al collage.

### Mejorar prompts con Claude (opcional)

En la caja de **Generar** y de **Vídeo** hay un botón **Mejorar** (⌘E). Envía tu idea a **Claude Haiku 5.5**, que la reescribe en inglés siguiendo las guías oficiales de prompting de FLUX 3 sin cambiar lo que pediste. Con imágenes de referencia escribe la edición como pide BFL: qué objetivo, qué cambia y en qué, y qué se conserva, con la imagen base como image 1. Debajo explica en español qué ha cambiado, y con **↶** vuelves a tu texto.

En **Editar** también está: junto a «Cambio en toda la imagen» y, con la varita pequeña, dentro de la tarjeta de cada región (Editar, Nuevo y Mover). Ahí Claude escribe una instrucción corta y concreta, pensada para encajar en el prompt de edición que monta la app (sin repetir posiciones ni cajas). ⌘E mejora la región abierta o, si no hay ninguna, el cambio global.

Para usarlo, crea una API key en https://console.anthropic.com → API Keys y pégala en **Ajustes → Mejorar prompts con Claude → Guardar en el Llavero**. Pulsa **Probar** para comprobarla. Cada mejora cuesta décimas de céntimo.

### Asistente de prompts (chat con Claude)

Un chat en un panel lateral para los prompts difíciles: quitarle a una imagen el aspecto de IA, llevarla al look de otra, o pulir un prompt que no sale. Se abre con **Asistente** en la barra lateral (o **⌘L**) y usa la misma API key de Anthropic que «Mejorar».

1. **Imágenes:** pulsa **Imagen en grande**, arrastra miniaturas de la tira o del Finder al panel, o clic derecho en una foto → **Enviar al asistente**. Cada una lleva un número (**#1**, **#2**…) y un papel que puedes cambiar: *Imagen a transformar*, *Referencia de estilo*, *Referencia* o *Resultado*. Si no añades ninguna, se usa la que tienes en grande.
2. **Pide lo que quieras** o usa un atajo: **Quitar aspecto de IA**, **Llevar al estilo de una referencia**, **Mejorar mi prompt**. ↩ envía; ⌥↩ hace salto de línea.
3. **Prompts con botones:** cada prompt que propone sale en una tarjeta con **Usar en Editar** (abre la imagen a editar con ese prompt ya puesto y las demás como referencias; «Ver prompt» lo enseña), **Usar en Generar** (prompt, referencias en orden, proporción y resolución) y **Copiar**.
4. **Itera:** genera, pulsa **Imagen en grande** para enseñarle el resultado y dile qué falla. Compara y corrige cambiando una cosa cada vez.

- **Modelo:** **Sonnet** por defecto (rápido y suficiente para casi todo) y **Opus** para casos difíciles, en el selector de arriba del panel.
- **Lo que sabe de FLUX:** lleva una guía de FLUX 3 Image (la del skill del estudio revisada con la documentación oficial de Black Forest Labs en docs.bfl.ml, leída el 1-11-2026, y sus skills oficiales): cómo escribir ediciones, quitar el aspecto de IA, transferir un estilo, citar referencias, texto, colores hex, layouts y parámetros. Puedes añadir notas propias (estilo de la casa, ópticas, trucos) en el menú del reloj → **Notas propias para la guía de FLUX…**, que crea `Asistente/guia-flux-extra.md` en la carpeta de salida; lo que escribas ahí se añade en cada conversación y tiene prioridad.
- **Conversaciones:** se guardan solas en `Asistente/` dentro de la carpeta de salida; el menú del reloj abre las recientes y el lápiz empieza una nueva.
- **Coste:** las imágenes se envían reducidas (1568 px) y la guía va en caché, así que una conversación normal con Sonnet cuesta céntimos; Opus cuesta el doble por token. Si un filtro de seguridad de Claude rechaza una petición, se reintenta sola con otro modelo.

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
  - `FluxCore`: cliente de la API (`BFLClient`, polling con timeout y cancelación), peticiones `Codable` de cada endpoint, construcción del prompt de Editar con precisión, máscara de Borrar y de Pintar y rellenar (pincel y polígono, borde suavizado y pegado sobre el original), geometría de Outpainting, guardado e historial, y `PromptEnhancer` para Claude Haiku. Todo con tests.
  - `FluxStudio`: interfaz SwiftUI (MVVM sencillo, `async/await`).
- `swift build` y `swift test` compilan y prueban el proyecto.
- `./build_app.sh` monta `FLUX Studio.app` en `~/Applications`; `./make_dmg.sh` crea `dist/FLUX-Studio.dmg`.
- GitHub Actions (`.github/workflows/build.yml`) compila, ejecuta los tests y comprueba que la app del instalador arranca en macOS en cada cambio. Cada cambio en la rama `claude/flux-studio-macos-app-afvdnk` publica además el `.dmg` en la release **ultima**, que es la que descarga `install.sh`.

### Comprobación contra la documentación de BFL

El 1-11-2026 se contrastaron con la referencia oficial de la API (docs.bfl.ml) todos los campos que envía la app:

- **FLUX 3 Image** (`flux-3-image`): `prompt`, `images`, `aspect_ratio`, `resolution` (también `match_input`), `safety_tolerance`, `grounding`. Correcto.
- **Ampliar** (`flux-tools/outpainting-v1`): `input_image`, `width`, `height` (mínimo 64), `prompt`, `reference_offset_x/y`, `auto_crop`, `mode` (`high`/`fast`), `disable_pup`, `safety_tolerance`, `output_format`. Correcto.
- **Borrar** (`flux-tools/erase-v1`): `image`, `mask` (blanco = borrar, mismo tamaño que la imagen), `dilate_pixels` (0–25), `seed`, `safety_tolerance`, `output_format`. Correcto.
- **Deblur** (`flux-tools/deblur-v1`): `image`, `seed`, `safety_tolerance`, `output_format`. Correcto.
- **Probador** (`flux-tools/vto-v2`): `prompt`, `person`, `garment`, `seed`, `safety_tolerance`, `output_format`, y la fórmula de prompt recomendada. Correcto.
- **Editar vídeo** (`flux-tools/video-edit-v1`): el campo es `video` (URL o mp4 en base64), con `prompt` de hasta 4096 caracteres. Correcto.
- **Regiones de Editar:** las filas de cajas siguen la tabla de la documentación de FLUX 3 («Edit an image box by box»): las regiones Editar y Nuevo son filas *New* (`from: null`, o la imagen de referencia de la región, con `tgt_bbox` y `desc`), Mover es una fila *Move* (caja de origen y de destino) y Proteger una fila *Keep* (misma caja de origen y destino). Las frases del prompt siguen siendo las de la herramienta oficial de Precise Editing.
