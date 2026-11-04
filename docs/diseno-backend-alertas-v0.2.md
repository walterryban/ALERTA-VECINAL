# VIGIARED — Diseño backend de alertas v0.2

**Estado:** especificación previa al SQL; no ejecutar ni desplegar.  
**Rama:** `integracion-segura-2026-11-04`  
**Alcance:** creación autenticada de alerta, difusión a integrantes autorizados, lectura COM, transición de estado y cola de notificaciones.

## 0. Principio de diseño

La alerta es una operación de seguridad, no un INSERT libre. Una única transacción valida la identidad y la membresía, determina el alcance desde relaciones persistidas, crea el registro operativo y encola avisos mínimos. El navegador nunca decide la organización, manzana, unidad, emisor ni destinatarios.

No se conecta todavía con `terminal.html` ni con `admin.html`. El esquema es una propuesta para revisión y posterior ensayo aislado.

## 1. Dependencias y orden de construcción

Los borradores existentes describen dependencias que deben tratarse como una única secuencia, no como scripts independientes:

1. **Red:** `establecimientos` y `unidades`, con pertenencia inequívoca a una manzana y organización.
2. **Identidad:** `perfiles_vecinales`, `membresias_vecinales`, invitaciones y auditoría.
3. **Alertas:** relación inequívoca alerta → unidad de origen → establecimiento → manzana → organización.
4. **Difusión/outbox:** evento mínimo y entregas por membresía/dispositivo.
5. **RBAC COM:** autorización de lectura y actualización por organización y permiso.
6. **Workers:** entrega externa con revalidación, lease y reintentos.

### Relación manzana-organización identificada en el diseño RBAC

La revisión de `docs/migracion-rbac-plataforma-municipios-v0.3-borrador.sql` identifica `manzanas.organizacion_id` como relación canónica prevista. El modelo RBAC la trata como una organización por manzana y aplica las políticas desde esa columna. Por lo tanto, el alcance de un establecimiento/unidad se deriva por `unidades → establecimientos → manzanas.organizacion_id`; no se debe duplicar `organizacion_id` en establecimientos o unidades.

**Pendiente de verificación:** esta relación está en un borrador RBAC, no acredita que exista en la base compartida. Antes del SQL final habrá que comprobar el DDL real en un proyecto aislado y definir migración si el esquema difiere. Si el producto llegara a requerir que una misma manzana pertenezca a varias organizaciones, el modelo actual de RBAC no alcanza y necesitaría una tabla puente con reglas explícitas; no asumir esa cardinalidad en esta versión.

### Inconsistencia de estados detectada

El borrador de red v0.1 permite `establecimientos.estado = 'pendiente'|'activo'|'suspendido'|'inactivo'` y `unidades.estado` con los mismos valores. El borrador de identidad v0.2 valida `activo`, lo cual es coherente. No se debe introducir un segundo vocabulario de estados para alertas que se confunda con el estado de unidad.

## 2. Contrato RPC: crear alerta

Nombre lógico propuesto: `crear_alerta_vecinal_v2`.

### Entrada permitida

- `p_tipo_alerta`: valor de catálogo cerrado y validado en servidor.
- `p_id_solicitud`: UUID idempotente generado para un intento lógico.
- `p_lat`, `p_lng`: opcionales, validados como par, rango geográfico y precisión razonable.
- `p_ubicacion_compartida`: confirmación explícita cuando se adjuntan coordenadas.
- `p_referencia`: opcional, longitud limitada y sin permitir HTML; definir si realmente es necesaria.

No se admiten `auth_user_id`, `perfil_id`, `membresia_id`, `unidad_id`, `establecimiento_id`, `manzana_id`, `organizacion_id`, domicilio, teléfono, ficha médica, prioridad ni destinatarios como autoridad del cliente.

### Validaciones servidor-lado

1. `auth.uid()` existe.
2. Perfil único activo asociado a ese Auth user.
3. Membresía activa del perfil en una unidad activa.
4. Establecimiento activo.
5. Unidad marcada `participa_red = true`.
6. Relación manzana-organización vigente, inequívoca y activa.
7. Catálogo de alerta permitido, límites por usuario/unidad y clave idempotente.
8. Ubicación válida y consentimiento presente si hay coordenadas.
9. El detalle operativo se obtiene desde la unidad/establecimiento y el perfil persistidos; el cliente no puede sobrescribirlo.

Si un perfil tiene varias membresías activas, el servidor no debe elegir silenciosamente. La primera versión debe requerir selección de contexto mediante un identificador de membresía opaco y validar que pertenece a `auth.uid()`; ese identificador selecciona entre autorizaciones reales, no crea una autorización. Alternativa: usar una membresía predeterminada explícitamente configurada. La RPC no aceptará una unidad arbitraria.

### Transacción atómica

- Insertar la alerta operativa en el almacenamiento privado.
- Insertar un registro de idempotencia vinculado a Auth user + clave.
- Insertar un evento de difusión con payload mínimo.
- Calcular destinatarios activos de la misma manzana/organización, solo unidades participantes.
- Insertar una entrega única por membresía destinataria.
- Registrar auditoría sin datos sensibles innecesarios.
- Confirmar todo junto; cualquier error revierte toda la operación.

Repetir la misma clave para el mismo usuario devuelve el resultado previo permitido, sin volver a crear alerta ni entregas. La misma clave de otro usuario no revela la existencia de la solicitud.

### Política de emisor

El emisor recibe confirmación en su propia sesión, no una notificación push redundante. Si el emisor pertenece a otra unidad de la misma manzana, puede recibir aviso comunitario como integrante de esa otra unidad, sujeto a política y deduplicación por membresía.

## 3. Esquema lógico de alertas y outbox

Nombres orientativos; no son DDL final.

### Registro operativo privado

Debe contener:
- ID, timestamp, tipo y estado operativo.
- Identidad y membresía de origen.
- Unidad y establecimiento de origen.
- Referencia a manzana/organización derivadas.
- Domicilio declarado, separado de coordenadas del dispositivo.
- Contacto y datos médicos solo si la finalidad lo requiere y con control de acceso reforzado.
- Coordenadas opcionales, consentimiento y fuente de ubicación.
- Clave idempotente y actor creador.

No duplicar datos personales en difusión. Si se conserva compatibilidad temporal con `public.alertas`, definir una transición versionada y evitar dos fuentes de verdad.

### Evento de difusión mínimo

- ID de evento, alerta_id, manzana_id/alcance derivado.
- Código de tipo de aviso permitido.
- Hora de creación y estado de procesamiento.
- Sin nombre, teléfono, domicilio, coordenadas, ficha médica ni descripción libre.

### Entregas por membresía

- ID, evento_id, membresia_id.
- Estado: `pendiente`, `procesando`, `aceptada_proveedor`, `entrega_confirmada`, `leida`, `fallida`, `cancelada`.
- Contador de intentos, `proximo_intento_at`, lease, timestamps y código de error normalizado.
- Restricción única evento + membresía.
- No almacenar token push en la fila de entrega.

### Dispositivos

Cada dispositivo pertenece a un perfil y tiene plataforma, token protegido, estado revocable, fechas de alta/uso y último resultado. El token debe cifrarse en backend con clave fuera de la base, o gestionarse mediante almacenamiento secreto equivalente. La clave no puede estar en HTML, repositorio ni variables públicas.

## 4. Worker de notificaciones

La Edge Function/worker:
1. Reclama un lote en una transacción usando `FOR UPDATE SKIP LOCKED`.
2. Marca `procesando`, establece lease y aumenta intento.
3. Fuera de la transacción, revalida membresía, unidad, establecimiento, organización y dispositivo.
4. Si el permiso ya no existe, cancela sin enviar.
5. Construye payload genérico con código de aviso, timestamp aproximado y enlace interno autenticado.
6. Envía al proveedor con identificador idempotente cuando el proveedor lo soporte.
7. Registra aceptación del proveedor, error o confirmación de entrega por separado.
8. Programa backoff exponencial con jitter y máximo de intentos; errores permanentes/token inválido revocan dispositivo.
9. Si el worker cae, el lease vence y otro worker puede reclamar la entrega sin duplicar el evento lógico.

El proveedor puede aceptar una solicitud sin que el dispositivo la reciba. No presentar aceptación como entrega confirmada. Web Push/FCM/APNs no garantiza recepción.

## 5. Lectura COM y control de estado

No usar `select('*')` desde el navegador ni traer todas las organizaciones para filtrar localmente.

Contratos lógicos:
- `listar_alertas_com_v2(filtros_paginacion)`: solo filas dentro del alcance de `auth.uid()`, rol y organización activa.
- `obtener_detalle_alerta_com_v2(alerta_id)`: datos operativos necesarios según permiso; los datos médicos quedan en permiso separado y auditoría específica.
- `cambiar_estado_alerta_com_v2(alerta_id, nuevo_estado, motivo, clave_idempotencia)`: valida rol y transición, bloquea fila, actualiza estado y agrega auditoría en la misma transacción.

La función de listado devuelve DTO explícito, no `SELECT *`. Paginación por cursor/fecha+ID, límites máximos, orden estable y filtros validados. Auditor municipal solo lectura. Operador puede ejecutar únicamente transiciones asignadas. Supervisor/administrador según matriz RBAC aprobada. Propietario global puede supervisar, pero toda consulta global debe quedar auditada y no convierte al municipio en administrador de plataforma.

Estados de alerta iniciales propuestos: `pendiente` → `en_proceso` → `resuelta`; permitir retorno o cancelación solo con reglas explícitas, motivo y auditoría. Mapear valores legados `EN PROCESO`/ `RESUELTA` durante migración sin alterar registros históricos hasta definir compatibilidad.

## 6. Privilegios y límites de seguridad

- RLS activado en tablas privadas y outbox.
- Sin SELECT/INSERT/UPDATE/DELETE directo de `anon` ni `authenticated` sobre outbox, tokens, detalle médico o tablas de auditoría.
- RPCs de usuario solo `authenticated`; funciones internas de worker solo rol backend específico.
- No usar `service_role` en frontend.
- Si una RPC usa `SECURITY DEFINER`: propietario mínimo y confiable, `SET search_path = ''`, nombres calificados, revocar EXECUTE a PUBLIC, validar cada parámetro, no construir SQL dinámico con entrada del usuario.
- Nunca aceptar un rol, organización o permiso enviado por cliente.
- No usar `es_operador()` como bypass global del RBAC nuevo.
- Registrar intentos denegados sin revelar si existe otra unidad/alerta.

## 7. Límites antiabuso y protección de datos

La primera versión debe incluir:
- Rate limit por cuenta y unidad; umbrales configurables por catálogo de alerta.
- Dedupe por clave idempotente y ventana temporal de tipo/unidad.
- Límite de longitud y normalización de entrada.
- CAPTCHA o desafío progresivo solo si se detecta abuso, sin bloquear emergencias legítimas.
- Alertas de abuso para COM/propietario con acceso restringido.
- Separar ubicación declarada de GPS del dispositivo.
- No solicitar ficha médica completa en una alerta comunitaria. Si existe ficha de emergencia, almacenarla aparte y exponerla solo bajo permiso específico y justificación.
- Política de retención/borrado por categoría antes de producción; no inventar plazos legales.
- Auditoría de lectura de datos sensibles, cambios de estado y exportaciones.

## 8. Decisiones de producto adoptadas para el primer diseño

- El emisor recibe confirmación en pantalla, no push duplicado a sí mismo.
- El push vecinal no identifica al emisor ni revela domicilio, ubicación, teléfono o datos médicos.
- El detalle del aviso vecinal es genérico; no hay endpoint de detalle personal del emisor para vecinos.
- La membresía se revalida al despachar, por lo que una revocación antes del envío cancela la entrega.
- Realtime actualiza sesiones activas, pero outbox + push son el canal durable.
- La prioridad se define en catálogo servidor-lado; no se acepta prioridad del cliente.
- Los datos médicos quedan fuera de la primera vista de operador hasta que se apruebe permiso y auditoría separados.

## 9. Pruebas de aceptación antes de integración

Además de AL-01 a AL-26 de `revision-alertas-com-v0.2.md`, añadir:

| ID | Prueba | Resultado requerido |
|---|---|---|
| AL-27 | Usuario con dos membresías activas no selecciona contexto | Solicitud exige contexto válido; no elige arbitrariamente |
| AL-28 | Usuario manipula membresía de otra cuenta | Rechazo sin revelar existencia |
| AL-29 | Unidad activa pero `participa_red=false` | No puede originar ni recibir difusión |
| AL-30 | Establecimiento/manzana sin organización inequívoca | Bloqueado hasta resolver asignación |
| AL-31 | Clave idempotente repetida por mismo usuario | Mismo resultado lógico, sin duplicar entregas |
| AL-32 | Misma clave enviada por otro usuario | Sin colisión ni filtración entre cuentas |
| AL-33 | Perfil suspendido tras encolar y antes de envío | Entrega cancelada por revalidación |
| AL-34 | Cambio de organización durante procesamiento | No envía fuera del alcance autorizado |
| AL-35 | Detalle médico sin permiso específico | Denegado; acceso auditado |
| AL-36 | Auditor COM intenta transición | Denegado por servidor aunque fuerce RPC |
| AL-37 | Reintento tras timeout del proveedor | No crea segundo aviso lógico |
| AL-38 | Evento push inspeccionado | Solo código genérico, hora aproximada y deep-link |
| AL-39 | Filtros COM manipulados para organización ajena | Cero datos ajenos |
| AL-40 | Actualización concurrente de estado | Una transición gana; otra revalida estado y falla o devuelve idempotencia |

Todas las pruebas se ejecutan en Supabase desechable con cuentas, domicilios, organizaciones y alertas sintéticas.

## 10. Pendientes que bloquean el SQL final

1. Verificar en un proyecto aislado que el DDL real coincide con la relación prevista `manzanas.organizacion_id` (una organización por manzana) del borrador RBAC v0.3.
2. Decidir si una alerta se guarda en `public.alertas` o en tabla nueva privada; no mantener dos fuentes activas.
3. Definir catálogo de tipos y mapeo con los botones actuales de la terminal.
4. Definir permiso separado para ficha médica y si se elimina de la primera versión.
5. Aprobar retención por categoría y texto legal/consentimiento para GPS.
6. Definir proveedor Push y secreto de cifrado; no configurar hasta disponer de entorno aislado.
7. Implementar inbox seguro de solicitudes para titulares, transferencia de titularidad y recuperación de cuenta antes de apertura pública.

## 11. Estado

Este documento es una especificación, no SQL ejecutable. No se modificaron las tablas actuales, no se ejecutaron migraciones, no se desplegó worker ni se conectó el frontend. Los datos ficticios actuales permanecen intactos.
