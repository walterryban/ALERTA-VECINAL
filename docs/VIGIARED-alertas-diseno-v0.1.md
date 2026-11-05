# VIGIARED — Diseño de alertas comunitarias v0.2

**Estado:** diseño técnico actualizado para revisión; no es una migración ejecutable.  
**Rama:** integracion-segura-2026-11-04.  
**Presupuesto:** cero pesos. No habilitar proveedores externos, SMS, WhatsApp ni notificaciones pagas.  
**Producción:** no ejecutar SQL ni desplegar funciones hasta completar revisión y pruebas.

## 1. Objetivo

Una persona con membresía activa genera una alerta desde su cuenta y domicilio. La alerta es un reporte compuesto por:

1. **Mensaje del vecino:** descripción breve de lo que sucede.
2. **Ubicación GPS del teléfono:** latitud/longitud, sólo si el vecino concede permiso y el dispositivo entrega una posición válida.
3. **Mapa de ubicación:** representación cartográfica de las coordenadas, para que el Centro de Monitoreo identifique el punto reportado.
4. **Vista de la zona mediante Google Street View:** referencia visual cuando Google disponga de cobertura para ese punto. Debe identificarse como imagen de referencia, no como fotografía en vivo ni prueba de que la escena siga igual.
5. **Fotografía propia del vecino:** complemento opcional, nunca requisito para enviar una alerta.

Los tres elementos, cuando estén disponibles, quedan asociados al mismo identificador de alerta. La alerta debe llegar:
- Al Centro de Monitoreo de la organización correspondiente.
- A todos los vecinos con membresía activa de la misma manzana, sin excepción por tipo de alerta.
- Al emisor, para mostrar confirmación y estado.

La autorización se calcula en el servidor. El navegador no decide quién recibe una alerta.

## 2. Destinatarios y alcance

- Emisor: usuario autenticado con membresía activa en la unidad desde la que reporta.
- Vecinos: todos los usuarios con membresía activa en unidades activas de la misma manzana y organización, para todos los tipos de alerta.
- Excluir membresías pendientes, suspendidas o revocadas.
- Si una persona tiene más de una membresía activa en la misma manzana, recibe una sola notificación por alerta.
- Centro de Monitoreo: propietario global con vista de supervisión; administrador y supervisor activos de la organización; operador activo con permiso operativo.
- Auditor: lectura de los registros autorizados, sin capacidad de crear alertas ni cambiar su estado.
- No enviar a otras organizaciones ni a otras manzanas.
- No incluir teléfono, correo ni ficha médica del emisor en la notificación vecinal.
- El detalle visible a vecinos debe ser mínimo y proporcional: tipo, mensaje, hora, manzana, referencia de domicilio y ubicación/foto si están autorizadas. Los datos identificatorios adicionales sólo estarán disponibles a roles autorizados y con justificación.

## 3. Modelo de datos propuesto

### `alertas`
- `id` UUID.
- `organizacion_id`, `manzana_id`, `unidad_id`.
- `creada_por` UUID del usuario autenticado.
- `tipo`: allowlist inicial `emergencia`, `asistencia`, `robo`, `coaccion`, `incendio`, `otra`.
- `mensaje` obligatorio, con longitud limitada y validación de contenido.
- `descripcion` opcional sólo si se justifica separarla del mensaje principal.
- `estado`: `pendiente`, `en_proceso`, `resuelta`, `cancelada`.
- `direccion_snapshot` y `manzana_snapshot` para conservar la referencia al momento del evento aunque luego se edite el domicilio.
- `latitud`, `longitud` opcionales, obtenidas del dispositivo con consentimiento explícito. No aceptar coordenadas arbitrarias como autoridad del domicilio; conservar también el domicilio registrado como referencia.
- `precision_gps_m` y `gps_obtenido_at` opcionales para indicar precisión y antigüedad de la posición, si el navegador las entrega.
- `created_at`, `updated_at`, `resuelta_at`.

### Fotografía y archivos adjuntos

La fotografía se almacenará como archivo privado, no como imagen incrustada en la fila de la alerta ni como dato público:
- Bucket privado propuesto en Supabase Storage: `alertas-evidencias`.
- Tabla de metadatos `alertas_adjuntos`: `id`, `alerta_id`, `storage_path`, `mime_type`, `size_bytes`, `created_at`, y usuario que adjunta.
- Primera versión: hasta una fotografía por alerta; formatos permitidos JPEG, PNG o WebP; límite de tamaño a definir en la implementación y validar también en servidor.
- El nombre del archivo debe ser generado por el servidor; no usar nombres aportados por el cliente como ruta.
- Bucket privado, sin enlaces públicos permanentes. Acceso mediante autorización de la alerta y URL firmada de corta duración o descarga autorizada.
- Validar tipo real del archivo, tamaño y permisos. No confiar sólo en la extensión o el MIME enviado por el navegador.
- Evitar almacenar EXIF innecesario; la ubicación oficial de la alerta se guarda como dato GPS separado y con consentimiento.
- Si la carga de la foto falla, la alerta de texto y GPS debe poder enviarse igualmente. La interfaz informa que no se adjuntó la fotografía.
- No mostrar fotos a usuarios de otras manzanas/organizaciones ni a membresías no activas.

### `alertas_destinatarios`
- `alerta_id`, `user_id`.
- `unidad_id` de la membresía destinataria.
- `estado_entrega` interno: `pendiente`, `notificada_en_sesion`, `vista`.
- `created_at`, `vista_at`.
- Restricción única por `alerta_id,user_id` para evitar duplicados si una persona tiene más de una membresía en la misma manzana.

La tabla de destinatarios fija quién estaba autorizado al momento de crear la alerta. El detalle y los adjuntos seguirán verificando autorización actual y reglas de privacidad; la baja posterior de una membresía no amplía el acceso.

## 4. Flujo transaccional

1. El cliente solicita permiso GPS y permite escribir el mensaje. La fotografía se puede tomar o seleccionar, pero nunca debe retrasar el envío urgente.
2. El cliente envía tipo, mensaje, ubicación opcional y referencia segura del archivo adjunto a una Edge Function con JWT.
3. La Edge Function valida sesión, formato, límites y autorización. No acepta `creada_por`, `organizacion_id`, `manzana_id`, `unidad_id` ni destinatarios decididos por el cliente.
4. Una RPC segura deriva el usuario desde la sesión, verifica membresía activa y obtiene organización, manzana, domicilio y dirección desde la base.
5. En una sola transacción crea la alerta, fija destinatarios activos de la misma manzana y registra auditoría. La relación con el adjunto se completa de forma controlada, evitando dejar archivos huérfanos si la creación falla.
6. La respuesta confirma que el servidor recibió el reporte; no afirma que un teléfono apagado o desconectado haya recibido una notificación.
7. El Centro de Monitoreo y los clientes vecinales autorizados actualizan su vista mediante Realtime protegido por RLS o canal privado. Debe probarse aislamiento antes de elegir la implementación final.
8. Un operador autorizado cambia el estado mediante RPC; se registra actor, estado anterior/nuevo y hora en auditoría.

## 5. Google Maps, Street View y fuente de datos

Se recupera como requisito funcional la experiencia probada en la aplicación original: al disponer de una ubicación GPS autorizada, el Centro de Monitoreo debe poder abrir/ver el mapa del punto y consultar la vista de la zona en Google Street View cuando exista cobertura.

Reglas de implementación:
- Las coordenadas GPS de la alerta son el dato de ubicación reportado por el dispositivo; el mapa y Street View son representaciones/referencias visuales distintas.
- La interfaz debe mostrar cuándo no hay GPS, cuándo Street View no tiene cobertura y cuándo el contenido de Google no puede cargarse.
- Street View no es una cámara en vivo ni demuestra el estado actual del lugar. Mostrarlo como referencia visual con la atribución correspondiente.
- **Primera opción sin clave API:** construir enlaces oficiales de Google Maps URLs con coordenadas. Para el mapa: `https://www.google.com/maps/search/?api=1&query=LATITUD%2CLONGITUD`. Para Street View: `https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=LATITUD%2CLONGITUD`. Estas URLs no requieren clave API y abren Google Maps en la app o navegador; Street View mostrará la panorámica más cercana disponible, si existe.
- En la primera versión, los controles «Ver mapa» y «Ver Street View» pueden abrir esas vistas oficiales en otra pestaña/ventana. No prometer una fotografía incrustada dentro del panel hasta verificar la implementación original y las condiciones técnicas.
- **No usar Street View Static API ni Maps Static API** para mostrar imágenes incrustadas en esta etapa: requieren clave y facturación habilitada y pueden generar cargos por solicitud.
- Respetar atribución, condiciones de uso, restricciones de almacenamiento/caché y políticas aplicables; no descargar ni republicar imágenes de Google como archivos propios. No activar APIs, claves con facturación ni servicios pagos sin verificar el coste y recibir autorización expresa.
- Si no se puede cargar Google Maps/Street View, la alerta debe seguir mostrando las coordenadas y el domicilio registrado; la consulta externa es complementaria y nunca bloquea el envío.

Supabase continúa siendo la fuente oficial de alertas, membresías, ubicaciones y permisos. En el código y documentación revisados para esta etapa no se encontró evidencia de que Google Sheets sea el almacenamiento operativo actual de VIGIARED. No se debe usar una hoja de cálculo como mecanismo de autorización, distribución en tiempo real ni almacenamiento principal de fotografías. Si luego se confirma una integración con Google Sheets, podrá evaluarse sólo como exportación o reporte administrativo no sensible, sin credenciales, PIN, teléfonos, coordenadas precisas ni enlaces privados a fotografías.

## 6. Entrega y límites de la primera versión

- Realtime significa actualización mientras la aplicación está abierta y conectada.
- No equivale a notificación push en segundo plano ni garantiza que el usuario vea la alerta.
- Push web/móvil, SMS y WhatsApp quedan fuera de esta versión hasta validar compatibilidad, privacidad, costes y autorización expresa.
- No presentar VIGIARED como servicio de despacho de emergencias ni como reemplazo de 911/107/100.
- La pantalla debe indicar claramente si el servidor recibió el evento, si el GPS fue compartido y si la foto se adjuntó.
- Si GPS o foto no están disponibles, la alerta debe poder enviarse con el mensaje y el domicilio registrado.

## 7. Seguridad y privacidad obligatorias

- Sin INSERT/UPDATE directo de alertas desde el navegador; operaciones mediante RPC/Edge Function.
- RLS ENABLED y FORCE; permisos mínimos y políticas explícitas para lectura en tiempo real y Storage.
- No confiar en IDs de organización, manzana, unidad o usuario enviados por el cliente.
- Comprobar membresía activa al crear la alerta y al consultar su detalle y adjuntos.
- No exponer la alerta a toda la organización por defecto: el alcance vecinal es la manzana.
- Idempotencia para evitar alertas duplicadas por doble toque o reintento de red.
- Rate limiting por cuenta y controles adicionales de abuso; sin recopilar datos personales innecesarios.
- Auditoría de creación, acceso relevante y cambios de estado, sin tokens ni datos sensibles.
- Ubicación GPS opcional, con consentimiento explícito; si no hay permiso, usar la dirección registrada del domicilio y marcar que no se obtuvo GPS del dispositivo.
- Foto opcional, privada y con retención/borrado definidos antes de producción.
- Botones accesibles, grandes y con texto; confirmación visual, sonora y vibratoria cuando el dispositivo lo permita.

## 8. Casos mínimos de prueba

| ID | Prueba | Resultado esperado |
|---|---|---|
| A-01 | Vecino con membresía activa crea alerta con mensaje | Se crea asociada al domicilio real de su membresía |
| A-02 | Alerta con GPS autorizado | Guarda coordenadas y precisión/fecha si disponibles |
| A-03 | GPS denegado o no disponible | Se permite enviar con domicilio registrado y se informa que no hay GPS |
| A-04 | Alerta con fotografía válida | Archivo privado asociado a la alerta y visible sólo a autorizados |
| A-05 | Foto excede límite o formato no permitido | Se rechaza el adjunto; la alerta de texto puede enviarse |
| A-06 | Fallo al subir fotografía | No se pierde el mensaje; la interfaz informa que no se adjuntó |
| A-07 | Todos los vecinos activos de la misma manzana | Reciben una sola notificación por alerta |
| A-08 | Membresía pendiente, suspendida o revocada | No recibe ni consulta la alerta |
| A-09 | Vecino de otra manzana u organización intenta consultar | Denegado |
| A-10 | Cliente intenta suplantar unidad/organización/usuario | Los valores se ignoran; servidor deriva el contexto |
| A-11 | Operador autorizado cambia estado | Cambio auditado |
| A-12 | Auditor intenta cambiar estado | Denegado |
| A-13 | Doble envío con la misma clave de idempotencia | Una sola alerta |
| A-14 | Aplicación cerrada o teléfono desconectado | No afirmar recepción push |
| A-15 | URL de foto compartida o usada por otra organización | Acceso denegado o URL expirada |
| A-16 | Google Sheets no está conectado | El sistema funciona desde Supabase sin depender de Sheets |

## 9. Decisiones aprobadas y pendientes

**Aprobadas:**
1. Todos los vecinos con membresía activa de la misma manzana reciben todas las alertas, sin excepción por tipo. Se excluyen membresías pendientes, suspendidas o revocadas.
2. La alerta contiene un mensaje del vecino.
3. La alerta incorpora ubicación GPS del vecino cuando autoriza y el dispositivo la proporciona.
4. El Centro de Monitoreo muestra el mapa de las coordenadas GPS y permite consultar Google Street View cuando haya cobertura, mediante integración oficial y respetando sus condiciones.
5. La fotografía propia del vecino es opcional y, si se adjunta, se almacena de forma privada.
6. Supabase permanece como fuente oficial de datos; no asumir que Google Sheets es parte del sistema hasta verificarlo.

**Pendientes antes de SQL:**
1. Definir qué datos exactos ven los vecinos y cuáles quedan sólo para operadores autorizados.
2. Definir si el estado `resuelta` lo puede cambiar sólo un operador o también el emisor.
3. Probar Realtime y Storage con RLS en una base aislada.
4. Recuperar el código original y comprobar si utilizaba Maps URLs o una API incrustada. La alternativa aprobada sin coste de API es abrir Maps/Street View mediante URLs oficiales; cualquier API facturable queda excluida sin autorización expresa.
5. Resolver la autenticación telefónica real sin coste antes de habilitar el alta vecinal productiva.
6. Definir retención y borrado seguro de fotografías opcionales.

**No ejecutar este documento como SQL.** Primero se aprueba el alcance, luego se construye una migración separada, pruebas automatizadas y revisión de seguridad.
