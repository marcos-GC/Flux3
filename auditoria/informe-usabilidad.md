# Informe de usabilidad · FLUX Studio

**Alcance:** auditoría hecha solo a partir del código, en la rama `claude/flux-studio-macos-app-afvdnk`, commit `d41c181`. La app es nativa de macOS y no se puede arrancar en el entorno de análisis (Linux), así que **no hay capturas**. Lo que depende de cómo se ve en pantalla va marcado como **[supuesto]**.
**Datos de uso:** la app no tiene analítica ni logs; lo he comprobado buscando en el código. **No hay datos de uso**, así que ningún hallazgo se basa en frecuencias reales.
**Rutas:** todas son relativas a `Sources/FluxStudio/`, salvo que empiecen por `Sources/FluxCore/`.

---

## 1. Resumen: los 5 problemas más importantes

**1. La imagen en la que trabajas puede cambiar sola y llevarse tu trabajo sin avisar.** Cuando termina cualquier petición, el resultado pasa a ser la imagen seleccionada, aunque en ese momento estés en otra (`App/AppState.swift:320`). Al cambiar de imagen, **Editar** descarta regiones, instrucciones y versiones (`App/PreciseEditModel.swift:129-135` → `reset()` en `:100-104`), y **Borrar** descarta la máscara pintada (`App/ToolModels.swift:138-141`, `:232-233`). En la práctica: lanzas 4 variantes, empiezas a marcar regiones en otra imagen, llega una variante y pierdes las regiones. Para un uso profesional, con varias peticiones en paralelo, es el problema más grave.

**2. "Generar" con una imagen seleccionada es ambiguo.** El escenario muestra la imagen en grande, pero al escribir un prompt y pulsar generar, esa imagen **no se usa**: solo se envían las referencias de la barra (`App/AppState.swift:174-194`). Lo lógico es pensar que el prompt se aplicará a la imagen que se ve. Las dos formas de usarla (Referencia o Editar) existen, pero en otros sitios.

**3. Acciones que borran trabajo sin confirmación ni deshacer.** El botón **Generar** de la barra lateral borra prompt, referencias y parámetros (`App/AppState.swift:368-377`, `Views/SidebarView.swift:32`). En Editar, **"Borrar todas"** y la tecla ⌫ eliminan regiones (`Views/PreciseEdit/EditToolbar.swift:16`, `Views/PreciseEdit/EditCanvas.swift:186`). **"Reutilizar"** sobrescribe el prompt que estuvieras escribiendo (`App/AppState.swift:341`). Ninguna pide confirmación ni se puede deshacer, salvo la máscara de Borrar.

**4. Comparar y gestionar resultados es lento.** Una petición puede dar de 1 a 4 imágenes, pero el escenario solo enseña una (`Views/Workspace/WorkspaceView.swift:315`). Para comparar hay que ir clic a clic por la tira. Además, la tira mezcla todo el historial sin agrupar por petición ni por sesión (`Views/Workspace/ResultStrip.swift:47`), y desde ella no se puede borrar, marcar favoritos ni seleccionar varias imágenes (`Views/Components/ResultActions.swift:14-34`).

**5. Vocabulario y controles poco coherentes.** La misma herramienta tiene nombres distintos según el sitio: "Ampliar" en la barra lateral (`App/AppState.swift:23`), "Outpainting" en "Enviar a" y en el Historial (`Views/Components/ResultActions.swift:30`, `App/ToolModels.swift:212`). Lo mismo pasa con "Probador" / "Probador virtual" y con "Editar" / "Editar con precisión". Cancelar aparece en tres sitios distintos según la herramienta, y los trabajos en curso de la tira no se pueden cancelar. Hay etiquetas técnicas ("Grounding", "(auto_crop)", "Ancla", "Ajustado") que obligan a saber cómo funciona la API.

---

## 2. Hallazgos

| ID | Pantalla / flujo | Problema | Evidencia | Gravedad |
|---|---|---|---|---|
| H01 | Estudio · cualquier petición | Cada resultado nuevo pasa a ser la imagen seleccionada, aunque estés trabajando en otra. Con varias peticiones en paralelo la selección cambia sola. | `App/AppState.swift:320` (`focusedURL = stored.fileURL`) | Alta |
| H02 | Editar | Seleccionar otra imagen (o que llegue un resultado, por H01) descarta regiones, instrucciones, referencias por región y versiones sin aviso. | `App/PreciseEditModel.swift:129-135` → `load()` → `reset()` `:100-104` | Alta |
| H03 | Borrar | Al cambiar de imagen se borra la máscara pintada sin aviso. | `App/ToolModels.swift:138-141`, `:232-233` (`didLoadInput → clearMask`) | Alta |
| H04 | Generar con imagen seleccionada | La imagen que se ve en grande no se usa al generar; solo cuentan las referencias. No hay nada en la interfaz que lo indique. | `App/AppState.swift:174-194` (solo `references`) | Alta |
| H05 | Barra lateral · Generar | Siempre reinicia (prompt, referencias y parámetros) sin confirmar ni poder deshacer. No hay forma de volver a Generar conservando lo escrito. | `App/AppState.swift:368-377`; `Views/SidebarView.swift:32` | Alta |
| H06 | Editar | "Borrar todas" y ⌫ eliminan regiones sin confirmación ni deshacer (⌘Z no aplica a regiones). | `Views/PreciseEdit/EditToolbar.swift:16`; `Views/PreciseEdit/EditCanvas.swift:186` | Media |
| H07 | Historial · detalle | "Mover a la Papelera" no pide confirmación. Se puede recuperar desde la Papelera de macOS, pero el aviso de "borrado" no queda claro. | `Views/HistoryView.swift:239-240` | Baja |
| H08 | Estudio · Reutilizar | "Reutilizar" sustituye el prompt y los parámetros actuales sin avisar y sin deshacer. | `App/AppState.swift:341` | Media |
| H09 | Tira de resultados | Muestra todo el historial mezclado: sin grupos por petición o día, sin borrar, sin favoritos, sin selección múltiple ni exportación. | `Views/Workspace/ResultStrip.swift:47`; `Views/Components/ResultActions.swift:14-34` | Media |
| H10 | Generar · 2–4 imágenes | Solo una variante se ve en grande; comparar exige ir clic a clic por la tira. | `Views/Workspace/WorkspaceView.swift:315` (escenario con una sola URL) | Media |
| H11 | Trabajos en curso | Cancelar está en tres sitios distintos y no existe en la tira, que es donde se ve el estado de cada trabajo. | `Views/PromptBarView.swift:87`; `Views/Tools/ToolsShared.swift:29`; `Views/PreciseEdit/PreciseEditBar.swift:98`; `Views/Workspace/ResultStrip.swift:32-46` | Media |
| H12 | Coherencia de nombres | Ampliar/Outpainting, Probador/Probador virtual, Editar/Editar con precisión. El filtro del Historial usa los nombres largos y no coincide con la barra lateral. | `App/AppState.swift:22-25`; `Views/Components/ResultActions.swift:29-34`; `App/ToolModels.swift:212,330`; `App/PreciseEditModel.swift:354` | Media |
| H13 | Claridad · etiquetas | Etiquetas técnicas: "Grounding (búsqueda externa)", "(auto_crop)", "Ancla", "Ajustado", "Desactivar mejora automática del prompt". | `Views/PromptBarView.swift:127`; `Views/Tools/OutpaintView.swift:27,37,39`; `Views/PreciseEdit/RegionInspector.swift:51` | Baja |
| H14 | Claridad · etiquetas | "1 imagen" en Generar y "1 resultado" en Editar para lo mismo; chip "Referencia" junto a "Referencias". | `Views/PromptBarView.swift:62`; `Views/PreciseEdit/PreciseEditBar.swift:68`; `Views/Workspace/WorkspaceView.swift:294` | Baja |
| H15 | Estados · vídeo seleccionado | Con un vídeo seleccionado se pueden abrir Borrar, Ampliar, Deblur y Probador, que fallan con "No se puede leer la imagen". | `Views/SidebarView.swift:22` (solo comprueba que haya selección); `App/ToolModels.swift:138` → `ImageEncoder` | Media |
| H16 | Estados · errores | Los errores salen en un aviso modal que bloquea la ventana. Si fallan varias peticiones a la vez, solo se ve el primer error. No hay acción de "Reintentar". | `Views/ContentView.swift:21`; `App/AppState.swift:254`; `App/PreciseEditModel.swift:376` | Media |
| H17 | Estados · trabajos largos | No hay aviso del sistema al terminar un trabajo largo (un vídeo tarda minutos) si estás en otra app. | Búsqueda: 0 usos de `UserNotifications` | Media |
| H18 | Generar / Vídeo | El coste solo se conoce después de enviar; no hay estimación previa (4K, ×4, vídeo Full HD…). | `App/AppState.swift` (`runJob`: el coste llega en `onSubmitted`) | Media |
| H19 | Accesibilidad · contraste | Texto blanco sobre el violeta #8B7CF6 ≈ **3,3:1** (mínimo 4,5:1) en números y etiquetas pequeñas de regiones, chips y fotogramas. | `Views/Theme.swift` (`regionPalette`); `Views/PreciseEdit/EditCanvas.swift` (etiqueta de `BoxEditor`) | Media |
| H20 | Accesibilidad · texto y lectores | 26 textos de 9–10 pt. Ningún `accessibilityLabel` en botones de solo icono (↶, ⓘ, ◀ ▶ ✕, zoom −/+). | Búsqueda en `Views/` | Media |
| H21 | Accesibilidad · apariencia | Fuerza el modo claro e ignora la preferencia del sistema. | `Views/ContentView.swift:19` | Baja |
| H22 | Teclado | Solo hay ⌘↩, ⌘E y ⌘Z (este último solo en Borrar). Faltan atajos para cambiar de herramienta, empezar de cero, recorrer la tira con flechas y deshacer regiones, y no hay menús de la app. | Búsqueda de `keyboardShortcut` en `Views/` | Media |
| H23 | Ventana pequeña | Con la ventana mínima (1000 px) quedan ~790 px para barras con 8–9 controles en una fila (Vídeo, Ampliar). Es probable que se corten o se compriman **[supuesto]**. | `Views/ContentView.swift:18`; `Views/SidebarView.swift:62`; `Views/Workspace/WorkspaceView.swift:47`; `Views/Tools/VideoBar.swift`, `Views/Tools/OutpaintView.swift` | Media |
| H24 | Borrar | El lienzo de la máscara no tiene zoom ni desplazamiento, lo que dificulta pintar detalles pequeños. Editar sí tiene zoom. | `Views/Tools/EraseView.swift:108` | Media |
| H25 | Rendimiento percibido | Con una herramienta abierta, cada clic en la tira recodifica la imagen a 2560 px y carga otra de 3000 px. Recorrer la tira deprisa puede ir a tirones **[supuesto]**. | `App/ToolModels.swift:138-141`; `Views/Workspace/WorkspaceView.swift:376-378` | Baja |
| H26 | Funcionalidad que falta | No hay organización por proyecto o cliente ni favoritos: los archivos se guardan solo por fecha **[supuesto: relevante para un estudio]**. | `Sources/FluxCore/ResultStore.swift` (`dayFolder`) | Media |
| H27 | Funcionalidad que falta | No hay botón de "variaciones" (repetir el mismo prompt) ni estilos o fragmentos de prompt guardados ("estilo de la casa"). | — (no existe en el código) | Media |
| H28 | Tira · estado vacío | La tira no explica nada cuando aún no hay resultados. | `Views/Workspace/ResultStrip.swift` (no hay rama vacía) | Baja |

---

## 3. Propuestas de mejora

**P01 · Selección estable.** Un resultado nuevo solo pasa a ser la imagen seleccionada si sigues en la imagen de la que sale (o en Generar sin imagen). En otro caso aparece en la tira marcado "Nuevo" y se muestra un aviso discreto, "Listo · Ver", que no interrumpe.
- *Por qué:* evita cambios de contexto involuntarios y pérdidas de trabajo.
- *Resuelve:* H01; mitiga H02 y H03.
- *Impacto:* alto. *Esfuerzo:* bajo.
- *Archivos:* `App/AppState.swift` (`runJob`), `Views/Workspace/ResultStrip.swift`.

**P02 · Conservar el trabajo en curso por imagen.** Guardar las regiones y la máscara pendientes de cada imagen, para recuperarlas al volver a ella. Si se prefiere algo más simple, preguntar "¿Descartar las regiones?" antes de cambiar.
- *Resuelve:* H02, H03.
- *Impacto:* alto. *Esfuerzo:* medio.
- *Archivos:* `App/PreciseEditModel.swift`, `App/ToolModels.swift` (`EraseModel`).

**P03 · Que Generar sepa qué hacer con la imagen seleccionada.** Cuando hay imagen seleccionada, la caja de Generar muestra un selector claro con tres opciones:
1. **Editar esta imagen:** se envía como `images[0]` con el prompt como cambio global.
2. **Usarla como referencia.**
3. **Imagen nueva** (no se usa).

La opción por defecto se decide contigo (ver preguntas abiertas).
- *Resuelve:* H04.
- *Impacto:* alto. *Esfuerzo:* medio.
- *Archivos:* `Views/PromptBarView.swift`, `App/AppState.swift` (`generateImage`).

**P04 · Separar "Nuevo" de "Generar".** El botón Generar de la barra lateral solo cambia de herramienta y conserva lo escrito. "Empezar de cero" pasa a ser una acción explícita: botón "Nuevo" en la caja y ⌘N, con confirmación si hay prompt o referencias, o bien un "Deshacer" durante unos segundos.
- *Resuelve:* H05.
- *Impacto:* alto. *Esfuerzo:* bajo.
- *Archivos:* `Views/SidebarView.swift`, `App/AppState.swift` (`startFresh`), `Views/PromptBarView.swift`, `App/FluxStudioApp.swift` (menú).

**P05 · Deshacer y confirmaciones donde se pierde trabajo.**
- ⌘Z / ⇧⌘Z para regiones en Editar.
- Confirmación en "Borrar todas".
- "Reutilizar" guarda el texto anterior y ofrece "Deshacer", igual que hace Mejorar.
- Confirmación al mover a la Papelera.
- *Resuelve:* H06, H07, H08.
- *Impacto:* medio. *Esfuerzo:* medio.
- *Archivos:* `App/PreciseEditModel.swift`, `Views/PreciseEdit/EditToolbar.swift`, `Views/PreciseEdit/EditCanvas.swift`, `App/AppState.swift`, `Views/HistoryView.swift`.

**P06 · Tira de resultados agrupada y gestionable.**
- Agrupar por petición (las variantes juntas) y por día ("Hoy", "Ayer").
- Acciones en la propia tira: ★ favorito, borrar, selección múltiple con ⌘ / ⇧ y "Exportar…".
- Filtro arriba: "Esta sesión · Favoritos · Todo".
- Estado vacío explicativo.
- *Resuelve:* H09, H28 y parte de H26.
- *Impacto:* alto. *Esfuerzo:* medio-alto.
- *Archivos:* `Views/Workspace/ResultStrip.swift`, `App/HistoryStore.swift`, `Sources/FluxCore/ResultStore.swift` (`GenerationRecord`: identificador de grupo y favorito).

**P07 · Vista de variantes.** Cuando una petición devuelve 2–4 imágenes, el escenario las muestra en cuadrícula, en su proporción real, hasta que eliges una. Un clic la selecciona; doble clic la amplía.
- *Resuelve:* H10.
- *Impacto:* alto. *Esfuerzo:* medio.
- *Archivos:* `Views/Workspace/WorkspaceView.swift` (`FocusedStage`), `App/AppState.swift` (agrupar resultados por petición).

**P08 · Cola de trabajos unificada.**
- Una ✕ en cada hueco animado de la tira para cancelar ese trabajo.
- El mismo control de "Cancelar" en todas las barras.
- Indicador "2 en curso" en la barra lateral.
- *Resuelve:* H11.
- *Impacto:* medio. *Esfuerzo:* bajo-medio.
- *Archivos:* `App/AppState.swift` (asociar cada trabajo a su tarea), `Views/Workspace/ResultStrip.swift`, `Views/Tools/ToolsShared.swift`, `Views/PromptBarView.swift`.

**P09 · Vocabulario único y sin jerga.**
- Una sola lista de nombres (Generar, Editar, Borrar, Ampliar, Deblur, Probador, Vídeo) en la barra lateral, "Enviar a", el Historial y los nombres de archivo.
- Renombrar etiquetas técnicas, por ejemplo:
  - "Grounding" → "Consultar referencias en internet";
  - "(auto_crop)" → "Recortar bordes sobrantes";
  - "Ancla" → "Proteger";
  - "Ajustado" → "Solo cambiar proporción";
  - "1 resultado" → "1 imagen".
- *Resuelve:* H12, H13, H14.
- *Impacto:* medio. *Esfuerzo:* bajo.
- *Archivos:* `App/AppState.swift`, `Views/Components/ResultActions.swift`, `App/ToolModels.swift`, `App/PreciseEditModel.swift`, `Views/PromptBarView.swift`, `Views/Tools/OutpaintView.swift`, `Views/PreciseEdit/RegionInspector.swift`, `Views/PreciseEdit/PreciseEditBar.swift`.

**P10 · Herramientas según el tipo de archivo.** Desactivar Editar, Borrar, Ampliar, Deblur y Probador cuando lo seleccionado es un vídeo, con un tooltip que explique por qué. En Vídeo, preseleccionar el modo que encaje (imagen → Imagen a vídeo; vídeo → Continuar).
- *Resuelve:* H15.
- *Impacto:* medio. *Esfuerzo:* bajo.
- *Archivos:* `Views/SidebarView.swift`, `App/AppState.swift` (`WorkspaceTool.needsImage`).

**P11 · Avisos que no bloquean.**
- Errores en un aviso lateral con acciones ("Reintentar", "Abrir Ajustes", "Subir tolerancia"), agrupados si fallan varios.
- Notificación del sistema cuando termina un trabajo de más de ~30 s y la app no está en primer plano.
- *Resuelve:* H16, H17.
- *Impacto:* medio. *Esfuerzo:* medio.
- *Archivos:* `Views/ContentView.swift`, `App/AppState.swift`, nuevo servicio de notificaciones.

**P12 · Coste estimado antes de generar.** Mostrar "≈ X créditos" junto al botón de generar, según resolución, número de imágenes, duración y modo, y el coste real en cada resultado.
- *Resuelve:* H18.
- *Impacto:* medio. *Esfuerzo:* medio. Necesita la tabla de precios oficial de BFL.
- *Archivos:* `Views/PromptBarView.swift`, `Views/Tools/VideoBar.swift`, nueva tabla de precios en `Sources/FluxCore`.

**P13 · Accesibilidad básica.**
- Etiquetas de región con un violeta más oscuro (p. ej. #6A57E0 ≈ 5,2:1 con blanco).
- Tamaño mínimo de 11 pt.
- `accessibilityLabel` en botones de solo icono.
- Respetar el modo oscuro como opción en Ajustes: claro por defecto, como ahora.
- *Resuelve:* H19, H20, H21.
- *Impacto:* medio. *Esfuerzo:* medio.
- *Archivos:* `Views/Theme.swift`, `Views/PreciseEdit/EditCanvas.swift`, componentes de `Views/`, `Views/ContentView.swift`.

**P14 · Atajos y menú de la app.**
- ⌘1…⌘7 para las herramientas, ⌘N para "Nuevo".
- ←/→ para recorrer la tira y ⌘⌫ para mandar a la Papelera.
- ⌘Z para regiones.
- Menús "Herramientas" e "Imagen" en la barra de menús, para descubrir las funciones.
- *Resuelve:* H22.
- *Impacto:* medio. *Esfuerzo:* bajo.
- *Archivos:* `App/FluxStudioApp.swift` (`commands`), `Views/Workspace/ResultStrip.swift`.

**P15 · Barras que se adaptan al ancho.** En ventanas estrechas, agrupar los controles secundarios en "Más opciones" o pasarlos a una segunda fila, y permitir ocultar la tira (⌥⌘T).
- *Resuelve:* H23.
- *Impacto:* medio. *Esfuerzo:* medio. Conviene verificarlo antes con capturas reales.
- *Archivos:* `Views/Tools/VideoBar.swift`, `Views/Tools/OutpaintView.swift`, `Views/PromptBarView.swift`, `Views/Workspace/WorkspaceView.swift`.

**P16 · Zoom en Borrar.** Reutilizar el zoom y el desplazamiento de Editar (`CanvasLayout`, `ZoomControls`) en el lienzo de la máscara.
- *Resuelve:* H24.
- *Impacto:* medio. *Esfuerzo:* medio.
- *Archivos:* `Views/Tools/EraseView.swift`, `Views/PreciseEdit/EditCanvas.swift`.

**P17 · Preparar las imágenes solo al generar.** Codificar la imagen al pulsar Generar, no al seleccionarla. Mostrar en el escenario una versión de ~1600 px y cargar la de alta resolución solo al hacer zoom.
- *Resuelve:* H25.
- *Impacto:* bajo-medio. *Esfuerzo:* bajo.
- *Archivos:* `App/ToolModels.swift`, `Views/Workspace/WorkspaceView.swift`.

**P18 · Proyectos, estilos y variaciones (más adelante).**
- Campo "Proyecto" al generar, que se convierte en subcarpeta y en filtro.
- Estilos guardados: fragmentos de prompt que se añaden con un clic.
- Botón "Variaciones", que repite el prompt de la imagen seleccionada.
- *Resuelve:* H26, H27.
- *Impacto:* alto **[supuesto]**. *Esfuerzo:* alto.
- *Archivos:* `Sources/FluxCore/ResultStore.swift`, `App/HistoryStore.swift`, `Views/PromptBarView.swift`, `Views/SettingsView.swift`.

---

## 4. Priorización

**Victorias rápidas (alto impacto, poco esfuerzo)**
1. P01 · Selección estable
2. P04 · Separar "Nuevo" de "Generar"
3. P09 · Vocabulario único y sin jerga
4. P10 · Herramientas según el tipo de archivo
5. P14 · Atajos y menú
6. P17 · Preparar las imágenes solo al generar

**Mejoras de fondo**
1. P03 · Generar con la imagen seleccionada (pendiente de tu decisión)
2. P02 · Conservar el trabajo en curso por imagen
3. P07 · Vista de variantes
4. P05 · Deshacer y confirmaciones
5. P08 · Cola de trabajos unificada
6. P06 · Tira agrupada y gestionable
7. P11 · Avisos que no bloquean
8. P13 · Accesibilidad básica
9. P16 · Zoom en Borrar

**Para más adelante**
1. P12 · Coste estimado (necesita la tabla de precios de BFL)
2. P15 · Barras adaptables (conviene verlo antes con capturas)
3. P18 · Proyectos, estilos y variaciones

---

## 5. Preguntas abiertas

1. **Generar con una imagen seleccionada (P03):** ¿qué esperáis por defecto al escribir un prompt con una imagen en pantalla: **editarla**, **usarla como referencia** o **crear una imagen nueva**?
2. **"Generar" en la barra lateral (P04):** ¿preferís que deje de reiniciar y que "empezar de cero" sea un botón aparte con ⌘N? ¿O mantenerlo como ahora, pero con "Deshacer"?
3. **Variantes (P07):** ¿soléis pedir 2–4 imágenes por petición? Si es así, la cuadrícula de comparación sube de prioridad.
4. **La tira (P06):** ¿debe mostrar todo el historial o solo la sesión o el proyecto actual?
5. **Proyectos (P18):** ¿trabajáis por proyecto o cliente? ¿Os serviría que cada proyecto fuera una subcarpeta con su nombre?
6. **Equipo y pantallas (P13, P15):** ¿cuántas personas la usan y en qué Macs (portátil de 13–14" o monitor grande)? ¿Alguien necesita texto más grande o modo oscuro?
7. **Coste (P12):** ¿os resulta útil ver una estimación antes de generar? Si es así, necesito la tabla de precios de vuestra cuenta de BFL.
8. **Datos de uso:** si queréis basar la próxima ronda en datos reales, podría añadir un registro local y anónimo de uso (qué herramienta y cuántas veces), que solo se guardaría en vuestro Mac. ¿Os interesa?
