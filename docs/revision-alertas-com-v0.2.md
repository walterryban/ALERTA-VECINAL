# VIGIARED — Revisión de alertas y Centro de Operaciones v0.2

**Estado:** auditoría estática del código y diseño; no es una migración ni habilita operaciones.  
**Rama:** `integracion-segura-2026-11-04`  
**Regla:** no ejecutar SQL, no desplegar funciones y no probar escrituras contra el Supabase compartido.

## 1. Hallazgos del código actual

### 1.1 COM consulta datos demasiado amplios desde el cliente

En `admin.html`, `cargarAlertas()` ejecuta `from('alertas').select('*')`. La pantalla luego filtra en JavaScript. Ese filtro visual no es una frontera de seguridad: el navegador ya recibió las filas devueltas por PostgREST.

**Requisito:** la consulta debe quedar limitada en servidor por RLS o por una RPC de lectura. El propietario podrá tener vista global; cada miembro municipal solo verá alertas de organizaciones y manzanas dentro de su alcance. El rol auditor será estrictamente de solo lectura. No se debe confiar en filtros enviados por el cliente.

### 1.2 Gestión de manzanas conserva un flujo heredado de PIN

La pestaña de gestión todavía presenta un campo PIN y `agregarManzana()` inserta directamente en `public.manzanas` desde el navegador. También consulta `manzanas` con `select('*')`. Aunque el QR ya no transporta el PIN, el PIN compartido sigue siendo parte del modelo de creación heredado y no debe convertirse en credencial vecinal.

**Requisito:** retirar PIN compartido del flujo nuevo. La creación/asignación de manzanas debe ser una operación autorizada en servidor, vinculada a una organización activa y auditada. El QR será público y solo abrirá VIGIARED o una invitación revocable; nunca concederá pertenencia.

### 1.3 Autorización visual y autorización real deben coincidir

El COM llama a `obtener_contexto_administrativo()` y falla cerrado si no hay contexto RBAC. Es correcto no volver al fallback global `es_operador()`. Sin embargo, variables como `puedeActualizarAlertas` o controles ocultos/deshabilitados solo mejoran la interfaz: no reemplazan las políticas de base de datos.

**Requisito:** cada lectura y transición de estado debe comprobar rol, organización, estado de membresía y alcance de la alerta en servidor. Un usuario con sesión Auth pero sin membresía no obtiene datos.

### 1.4 Estado operativo y auditoría

La interfaz debe tratar las transiciones como comandos autorizados, no como un UPDATE libre desde el navegador. Definir una máquina de estados explícita, registrar actor, organización, estado anterior/nuevo, fecha y motivo, y rechazar transiciones inválidas o repetidas. Auditoría y cambio de estado deben ocurrir en una misma transacción.

### 1.5 Ubicación y privacidad

El COM puede necesitar domicilio declarado, coordenadas GPS, contacto y datos médicos pertinentes para responder. Son datos operativos sensibles y deben quedar disponibles solo para roles expresamente autorizados. La ubicación GPS del dispositivo y el domicilio declarado son campos distintos y deben rotularse como tales.

La red vecinal nunca recibe nombre, teléfono, domicilio exacto, ficha médica, coordenadas ni texto libre del emisor. El aviso comunitario debe ser mínimo y uniforme; el detalle solo se consulta autenticado y con autorización específica.

### 1.6 Realtime y sonido

Realtime sirve para actualizar sesiones conectadas; no garantiza recepción con la app cerrada. Debe manejar reconexión, eventos repetidos y pestaña en segundo plano. El sonido requiere activación explícita del usuario por las restricciones del navegador. No mostrar “entregada” por el solo hecho de que Realtime recibió un evento o el proveedor aceptó una solicitud.

## 2. Modelo de autorización de alertas propuesto

La autorización se deriva exclusivamente en servidor:

1. La sesión autenticada identifica al usuario mediante `auth.uid()`.
2. El perfil debe existir y estar activo.
3. Debe existir una membresía vecinal activa en la unidad que origina la alerta.
4. La unidad y el establecimiento deben estar activos y participar de la red.
5. El servidor obtiene establecimiento, manzana y organización desde las relaciones persistidas. No acepta `manzana_id`, `organizacion_id`, destinatarios, domicilio ni identidad como autoridad del navegador.
6. El servidor crea la alerta operativa y el evento de difusión en una transacción.
7. La audiencia se calcula desde las membresías activas de unidades participantes de esa manzana y organización. No se consultan ni notifican otras organizaciones.
8. Se genera una entrega única por membresía/evento. La revocación impide nuevas difusiones; las entregas ya encoladas requieren una política explícita de cancelación/revalidación al despachar.

La identidad del emisor se obtiene del perfil y la membresía; el cliente solo aporta los datos mínimos del evento (tipo permitido, descripción acotada si se justifica, ubicación GPS opcional y consentimiento/confirmación). No debe poder suplantar a otra persona.

## 3. Separación de canales

| Destino | Datos permitidos |
|---|---|
| COM autorizado | Detalle operativo estrictamente necesario: tipo, hora, domicilio declarado, GPS si existe, contacto y datos adicionales según rol y finalidad |
| Aviso push vecinal | Tipo genérico, hora aproximada y enlace interno autenticado; sin datos personales ni médicos |
| Pantalla de detalle vecinal | Solo datos mínimos que la política permita a ese integrante; nunca ficha médica/contacto del emisor por defecto |
| Auditoría | Actor, alcance, acción, resultado, referencia y marcas de tiempo; evitar copiar datos médicos o tokens |

No se debe prometer confidencialidad absoluta entre vecinos si la naturaleza del evento permite inferir el domicilio. La interfaz debe explicar qué información se comparte en cada canal.

## 4. Requisitos de implementación del backend

La futura migración/RPC deberá resolver, antes de conectar el frontend:

- **RPC de creación:** transacción única para validar membresía, validar tipo y límites, insertar alerta, insertar difusión y crear entregas. Idempotencia obligatoria mediante clave de solicitud generada por cliente pero única por usuario; la clave no otorga autoridad.
- **Destinatarios:** cálculo servidor-lado por organización, manzana y membresías activas; deduplicación por perfil/membresía y política explícita sobre incluir al emisor.
- **Outbox durable:** estados separados para pendiente, en proceso, aceptada por proveedor, entregada confirmada, leída, fallida y cancelada; lease/claim con expiración, reintentos con backoff y máximo de intentos.
- **Concurrencia:** claim de trabajos con `FOR UPDATE SKIP LOCKED`; el worker no debe procesar simultáneamente la misma entrega.
- **Push:** tokens protegidos, revocables por dispositivo y nunca devueltos al cliente. Los secretos del proveedor permanecen en Edge Function/entorno servidor.
- **Revalidación:** al enviar push, comprobar que la membresía y dispositivo siguen habilitados. Definir qué pasa con la cola si se revoca una membresía.
- **RLS y grants:** tablas sensibles sin SELECT/INSERT/UPDATE directo desde anon/authenticated. RPC con `SECURITY DEFINER` solo si hace falta, `search_path = ''`, propietario confiable, validación de parámetros y EXECUTE mínimo.
- **COM:** lecturas acotadas por organización en servidor; detalle médico en endpoint/consulta separada con permiso y auditoría; transiciones de estado atómicas.
- **Retención:** plazos diferenciados para alerta operativa, detalle médico, ubicación, entregas y auditoría; borrado/anonimización conforme a política aprobada.
- **Abuso:** límites por cuenta, unidad y ventana temporal; protección contra spam, doble toque, automatización y cuentas comprometidas.
- **Resiliencia:** sin GPS, sin red, proveedor caído, token inválido, navegador cerrado, pérdida de sesión y reconexión.

## 5. Casos de prueba obligatorios

| ID | Prueba | Resultado requerido |
|---|---|---|
| AL-01 | Usuario anónimo intenta crear alerta | Rechazado |
| AL-02 | Auth sin perfil activo | Rechazado |
| AL-03 | Perfil sin membresía activa | Rechazado |
| AL-04 | Membresía revocada/suspendida | Rechazado |
| AL-05 | Unidad o establecimiento suspendido | Rechazado |
| AL-06 | Cliente manipula manzana/organización/destinatarios | Valores ignorados o solicitud rechazada |
| AL-07 | Usuario de unidad A intenta crear en unidad B | Rechazado |
| AL-08 | Alerta válida | Alerta, difusión y outbox en una transacción |
| AL-09 | Reintento con misma clave idempotente | Un solo evento |
| AL-10 | Dos solicitudes concurrentes idénticas | Una sola alerta lógica |
| AL-11 | Miembros activos de la manzana | Reciben una entrega cada uno |
| AL-12 | Unidad no participante o de otra manzana | No recibe entrega |
| AL-13 | Unidad de otra organización | No recibe entrega |
| AL-14 | Payload push inspeccionado | Sin identidad, teléfono, domicilio, GPS, ficha médica ni texto libre |
| AL-15 | Membresía revocada antes del despacho | Entrega cancelada/no enviada según política |
| AL-16 | Worker concurrente reclama misma entrega | Un solo worker obtiene lease |
| AL-17 | Proveedor push falla | Reintento con backoff, sin duplicar evento |
| AL-18 | Proveedor acepta solicitud | Estado no equivale a entrega confirmada |
| AL-19 | COM admin organización A consulta B | Cero datos de B |
| AL-20 | Operador intenta cambiar estado sin permiso | Rechazado |
| AL-21 | Auditor intenta cambiar estado | Rechazado |
| AL-22 | Transición inválida o repetida | Rechazada/idempotente y auditada |
| AL-23 | Consulta de ficha médica sin permiso | Denegada y auditada |
| AL-24 | Sin GPS o ubicación denegada | Alerta sigue el flujo permitido sin inventar coordenadas |
| AL-25 | Realtime se desconecta y reconecta | Recupera estado sin duplicar filas ni sonido |
| AL-26 | Push con app cerrada | Resultado medido en dispositivo; no inferido desde Realtime |

Las pruebas deben ejecutarse con cuentas y domicilios sintéticos en un proyecto Supabase aislado. No usar el proyecto compartido de Preview/Producción.

## 6. Decisiones pendientes antes del SQL v0.2

1. ¿El emisor recibe también el aviso comunitario? Recomendación: no crear una segunda notificación redundante al emisor; confirmar el envío en su propia sesión.
2. ¿Qué ve un vecino al abrir el aviso? Recomendación: solo tipo, hora y orientación general; nada que identifique al emisor.
3. ¿Qué prioridad y caducidad tiene cada tipo de alerta? Definir por catálogo, sin permitir prioridad arbitraria del cliente.
4. ¿Cuándo se cancela una entrega encolada tras revocación? Recomendación: revalidar membresía justo antes del envío.
5. ¿Qué roles del COM pueden ver datos médicos? Recomendación: permiso separado, mínimo y auditado; no todos los operadores por defecto.
6. ¿Cuánto tiempo se conservan detalle, GPS, ficha médica, entregas y auditoría? Requiere política explícita.

## 7. Conclusión

La base v0.1 de difusión es un esquema inicial, no un backend de notificaciones funcional. No debe ejecutarse ni conectarse a la terminal todavía. Antes hay que consolidar el modelo de red/organización, resolver las decisiones de privacidad, diseñar RPC y worker, y probar permisos y concurrencia en un Supabase aislado.

La auditoría encontró además que el COM actual hace consultas amplias desde el navegador y mantiene la creación heredada de manzanas con PIN. Aunque RBAC falle cerrado al iniciar sesión, eso no demuestra que las consultas y mutaciones estén aisladas. La seguridad final debe estar en PostgreSQL/RPC, no en filtros o controles visuales.
