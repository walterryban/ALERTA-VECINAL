# VIGIARED — Reconciliación de distribución de alertas v0.2

**Estado:** revisión de arquitectura y criterios; NO es SQL ejecutable.  
**Rama:** integracion-segura-2026-11-04.  
**Seguridad de cambios:** no ejecutar migraciones, no desplegar Edge Functions y no modificar Supabase compartido ni producción.

## 1. Regla funcional confirmada

Una alerta válida creada por un vecino se registra una sola vez y debe estar disponible para:

1. El Centro de Monitoreo de la organización autorizada.
2. Todos los vecinos con membresía activa en domicilios/unidades pertenecientes a la misma manzana.
3. El emisor, mediante confirmación en su propia sesión; no se crea una notificación redundante para su mismo dispositivo/cuenta.

La distribución no depende del tipo: emergencia, asistencia, robo, coacción, incendio u otro tipo permitido se difunden a la misma audiencia autorizada.

Se excluyen membresías pendientes, suspendidas o revocadas, unidades inactivas y usuarios sin autorización vigente. Si una persona tiene varias membresías activas dentro de la manzana, recibe una sola notificación por alerta.

## 2. Correcciones de coherencia respecto de los documentos anteriores

### 2.1 No retirar el PIN individual de domicilio

La indicación anterior de «retirar el PIN compartido» no debe interpretarse como eliminar el ingreso vecinal QR + PIN aprobado por el producto.

El flujo aprobado sigue siendo:
- QR público de la manzana, sin PIN ni datos personales.
- PIN único por domicilio, generado en servidor y no incluido en QR, URL, logs ni analítica.
- Cada persona tiene cuenta individual; el PIN identifica el domicilio y permite solicitar incorporación.
- La solicitud se aprueba por un responsable/rol autorizado.
- El PIN se puede rotar/revocar sin borrar membresías ya aprobadas.

El PIN no se utiliza para decidir destinatarios ni para autorizar consultas de alertas. La autorización efectiva proviene de la sesión y de una membresía activa persistida.

### 2.2 No introducir tablas o relaciones heredadas sin validación

El diseño backend v0.2 menciona `establecimientos`, `perfiles_vecinales`, `membresias_vecinales` y `organizaciones_municipales`. Esos nombres no coinciden con el esquema base v0.1 que se verificó en el proyecto Supabase compartido: `organizaciones`, `perfiles`, `membresias_organizacion`, `membresias_unidad`, `unidades`, `solicitudes_ingreso` y `auditoria`.

Por lo tanto:
- No copiar ni ejecutar SQL basado en los nombres del borrador backend anterior.
- Reutilizar el esquema actual cuando sea correcto y extenderlo con migraciones versionadas sólo después de ensayar en una base aislada.
- No dar por existentes `manzanas`, `establecimientos`, `alertas_destinatarios`, `difusiones_comunitarias` ni `entregas_notificacion_vecinal` en el proyecto real.
- No asociar registros ficticios históricos por coincidencia de nombre, dirección o teléfono.

### 2.3 Falta definir una relación inequívoca domicilio → manzana

El esquema verificado tiene `unidades` con `organizacion_id` y dirección, pero no acredita una columna `manzana_id` ni una tabla de manzanas en la arquitectura v0.1.

No usar nombres de manzana, dirección ni texto libre como clave de distribución. Antes del SQL de alertas debe decidirse y probarse una relación estable entre cada unidad/domicilio y una manzana. El QR de manzana debe apuntar a esa entidad identificable, no a un texto que pueda repetirse.

La organización sigue siendo el límite multi-tenant. La manzana es el límite comunitario de difusión dentro de esa organización. No asumir que una organización equivale siempre a una sola manzana.

## 3. Flujo lógico de una alerta

1. El usuario inicia sesión individualmente.
2. El servidor valida perfil y membresía activa en la unidad desde la que se reporta.
3. La unidad y la manzana están activas y pertenecen a la organización autorizada.
4. El cliente envía sólo tipo permitido, mensaje limitado, clave de idempotencia y, opcionalmente, GPS con consentimiento y referencia a fotografía propia.
5. El servidor deriva usuario, unidad, manzana, organización, domicilio y destinatarios desde relaciones persistidas. Ignora o rechaza esos identificadores si el cliente intenta imponerlos.
6. En una transacción se crea el registro operativo único, la auditoría, el evento de difusión y las entregas lógicas.
7. El COM autorizado consulta esa misma alerta mediante una lectura servidor-lado limitada por rol/organización.
8. Los vecinos activos de la misma manzana reciben un aviso mínimo y uniforme. Los datos detallados se muestran sólo si una política de lectura vecinal explícita lo permite.
9. La sesión del emisor recibe confirmación de recepción del servidor.
10. La cola se procesa con reintentos e idempotencia. Antes del envío externo se revalida la membresía; una baja previa al despacho cancela la entrega.

## 4. Fuente única y no duplicación

- Debe existir un único registro operativo de alerta, con un identificador estable.
- COM, inbox vecinal, Realtime y cualquier futuro canal push hacen referencia a ese mismo identificador.
- El evento/outbox es una instrucción de distribución, no una segunda alerta ni un segundo almacén operativo.
- La creación de alerta, auditoría y creación de entregas lógicas deben ser atómicas.
- Restricción única recomendada: evento + usuario destinatario para notificación lógica, y/o evento + membresía según la política final. Para este producto se debe deduplicar por usuario dentro de la manzana, incluso si tiene varias membresías activas.
- Los reintentos actualizan la misma entrega lógica; nunca crean otra alerta.
- COM no debe recibir una alerta duplicada por cada destinatario vecinal.

## 5. Privacidad por canal

| Canal | Contenido mínimo |
|---|---|
| Centro de Monitoreo | Detalle operativo permitido por rol: tipo, mensaje, hora, domicilio registrado, GPS si fue compartido y referencias de evidencia autorizadas |
| Aviso vecinal | Tipo/categoría, hora aproximada y aviso genérico; sin nombre, teléfono, domicilio exacto, GPS, ficha médica ni texto libre |
| Detalle vecinal | Sólo la información que se apruebe expresamente para miembros activos de esa manzana; no exponer datos médicos ni contacto del emisor por defecto |
| Emisor | Confirmación de recepción y estado visible de su propio reporte |
| Auditoría | Actor, acción, entidad, alcance y timestamps; evitar copiar mensajes sensibles, tokens o datos médicos |

El hecho de que un usuario pertenezca a la manzana no le concede automáticamente acceso al domicilio exacto, identidad o evidencia del denunciante. La vista vecinal de detalle queda pendiente de una matriz de datos/roles explícita.

## 6. COM y modelo de roles

- Propietario global: supervisión de toda la plataforma, con acceso global auditado.
- Administrador de organización: gestiona sólo su organización y sus operadores.
- Supervisor/operador: acceso operativo según permisos explícitos de su organización.
- Auditor: lectura autorizada, sin crear alertas ni cambiar estados.
- Ningún rol municipal administra otras organizaciones ni la configuración global.

La consulta COM debe devolver campos explícitos y paginados desde servidor. No usar `select('*')` para traer alertas amplias y luego filtrar en JavaScript. Los cambios de estado deben ser RPC/operaciones autorizadas y auditadas en una transacción.

## 7. Realtime y notificaciones: alcance realista de primera versión

- Realtime actualiza las pantallas abiertas y conectadas; no garantiza recepción con la aplicación cerrada.
- La cola durable conserva trabajo pendiente y evita perder el evento por una desconexión del navegador.
- Push web/móvil requiere proveedor, tokens protegidos, configuración y pruebas en dispositivos. No se habilita en esta etapa ni se presupone coste cero.
- SMS y WhatsApp quedan fuera de alcance hasta revisar coste, verificación y autorización.
- Estados separados: pendiente, procesando, aceptada por proveedor, entrega confirmada (sólo con evidencia real), leída, fallida o cancelada.
- Nunca mostrar «entregada» si sólo hubo confirmación del servidor, evento Realtime o aceptación del proveedor.

## 8. Matriz de pruebas de distribución

| ID | Caso | Resultado esperado |
|---|---|---|
| DIST-01 | Alerta válida en manzana A | Una alerta operativa única |
| DIST-02 | Tres vecinos activos en domicilios de manzana A | Una entrega lógica por usuario |
| DIST-03 | Un usuario con dos membresías activas en A | Una sola notificación para ese usuario |
| DIST-04 | Miembro pendiente en A | No recibe |
| DIST-05 | Miembro suspendido en A | No recibe |
| DIST-06 | Miembro revocado en A | No recibe |
| DIST-07 | Unidad inactiva en A | No recibe y no puede originar alertas |
| DIST-08 | Vecino activo de manzana B | No recibe alerta de A |
| DIST-09 | Vecino de otra organización | No recibe alerta de A |
| DIST-10 | Tipos emergencia/asistencia/robo/coacción/incendio | Todos usan la misma regla de audiencia |
| DIST-11 | Cliente envía IDs de otra manzana | Servidor los ignora/rechaza; deriva alcance real |
| DIST-12 | Doble toque o reintento de creación | Una alerta y una sola entrega lógica por usuario |
| DIST-13 | Dos workers reclaman la misma entrega | Sólo un lease válido |
| DIST-14 | Membresía revocada antes del despacho | Entrega cancelada |
| DIST-15 | Worker falla después de reclamar | Reintento de la misma entrega sin duplicación |
| DIST-16 | Push aceptado pero móvil sin conexión | No se marca como entregado ni leído |
| DIST-17 | Payload vecinal inspeccionado | No contiene identidad, dirección exacta, GPS, ficha médica ni mensaje libre |
| DIST-18 | COM consulta alerta de otra organización | Cero datos ajenos |
| DIST-19 | Auditor intenta cambiar estado | Rechazo servidor-lado |
| DIST-20 | Misma alerta vista por COM y vecinos | Mismo ID de alerta; no se crean dos reportes |

## 9. Bloqueos antes de diseñar la migración

1. Resolver y verificar la relación de base entre unidades/domicilios y manzanas, compatible con el QR de manzana.
2. Confirmar la fuente única de alertas y sus columnas/tipos en un entorno aislado; no asumir que el esquema heredado `public.alertas` coincide.
3. Definir campos exactos que pueden ver los vecinos al abrir una alerta.
4. Definir el catálogo de tipos y la máquina de estados.
5. Definir el alcance de miembros de una manzana: todas las unidades activas asociadas, sin una bandera `participa_red` que excluya vecinos aprobados salvo que el usuario apruebe expresamente esa excepción.
6. Diseñar RLS/RPC y pruebas de aislamiento para el esquema real.
7. Definir outbox, deduplicación por usuario, retención y worker. Push externo queda deshabilitado en el presupuesto actual.

## 10. Estado y límites

Este documento reconcilia decisiones y detecta incompatibilidades; no modifica código de aplicación ni esquema de base. No se ejecutó SQL, no se desplegó una Edge Function, no se enviaron notificaciones reales y no se tocaron los datos ficticios ni producción.

La siguiente implementación debe empezar con una prueba aislada de relaciones y destinatarios, usando usuarios, organizaciones, manzanas y domicilios sintéticos. Sólo después de pasar las pruebas se prepara una migración versionada para revisión.
