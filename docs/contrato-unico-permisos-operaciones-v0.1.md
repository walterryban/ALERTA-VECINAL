# VIGIARED — Contrato único de permisos y operaciones v0.1

**Estado:** contrato de diseño para consolidación; no es SQL ni habilita accesos.  
**Rama:** `integracion-segura-2026-11-04`  
**Precedencia:** este contrato sustituye interpretaciones dispersas de los borradores RBAC/red/alertas cuando se prepare la migración consolidada. No modifica por sí mismo los scripts anteriores.

## 1. Principios no negociables

1. Denegar por defecto: sesión Auth no equivale a autorización.
2. La identidad se obtiene de `auth.uid()`; el navegador no puede suplantar actor, rol ni alcance.
3. Una organización municipal nunca administra otra organización ni la configuración global.
4. El propietario de plataforma es una identidad separada; ningún administrador municipal puede otorgar ese rol.
5. La pertenencia vecinal se obtiene de perfiles y membresías individuales, no de PIN compartido ni de la tabla histórica `vecinos`.
6. Unidades, establecimientos y manzanas deben estar activos para originar o recibir alertas.
7. La alerta se origina en una membresía/unidad autorizada; la manzana y organización se derivan de relaciones persistidas.
8. Lecturas y comandos se autorizan en servidor. Ocultar botones o filtrar en JavaScript no es seguridad.
9. Los datos personales y médicos se minimizan por finalidad y permiso.
10. Toda operación privilegiada deja auditoría atómica; si falla la auditoría, falla el comando.

## 2. Fuentes de autoridad

| Dominio | Fuente de verdad | No usar como autoridad |
|---|---|---|
| Cuenta | `auth.users` y `auth.uid()` | correo enviado por cliente |
| Perfil vecinal | `perfiles_vecinales` | `vecinos` legado |
| Acceso a domicilio/unidad | `membresias_vecinales` activas | QR, PIN, nombre o teléfono |
| Red física | `establecimientos`, `unidades`, FK a `manzanas` | texto libre de domicilio |
| Organización municipal | `manzanas.organizacion_id` según RBAC v0.3 | filtro del navegador |
| Rol municipal | `membresias_municipales` activas | tabla heredada `operadores` |
| Propietario global | `propietarios_plataforma` activo | rol municipal o correo |
| Alerta nueva | unidad de origen + relaciones derivadas | `p_manzana` o destinatarios del cliente |
| Difusión | outbox/entregas del servidor | Realtime como garantía de entrega |

**Nota de esquema:** varias fuentes son todavía borradores. La autoridad lógica aquí definida debe verificarse contra DDL real en un proyecto aislado antes de escribir SQL final.

## 3. Roles y alcance

### Plataforma
- `propietario_plataforma`: supervisión global y administración de organizaciones bajo comandos explícitos y auditados.
- El propietario no se crea desde UI pública, no se autoasigna y no se concede desde administración municipal.
- Toda consulta global de información operativa queda auditada.

### Organización municipal
- `administrador_municipal`: gestiona membresías y configuración operativa de su propia organización; no administra otros tenants ni el propietario.
- `supervisor_municipal`: supervisa alertas y equipos dentro de su organización; no gestiona roles privilegiados.
- `operador_municipal`: atiende alertas y ejecuta transiciones expresamente permitidas.
- `auditor_municipal`: lectura dentro de su organización; no cambia estados, usuarios ni configuración.

Una persona podría tener membresías en más de una organización solo si se crea una autorización explícita por cada una. Cada petición resuelve su alcance; no existe un rol municipal global implícito.

### Red vecinal
- Una cuenta puede tener varios perfiles/membresías según el modelo de identidad aprobado; una membresía corresponde a una unidad.
- Una persona puede integrar más de una unidad; revocar una membresía no revoca las otras.
- Titular y miembros autorizados se gestionan mediante flujo de invitación/solicitud y aprobación, con prevención de autoaprobación.
- No existe límite artificial de integrantes por unidad en el modelo de producto; sí controles de abuso, auditoría y revocación individual.
- Edificios, habitaciones, departamentos, hostels y comercios se modelan como establecimientos y unidades separadas. La participación en la red se habilita por unidad, no por dirección completa.

## 4. Matriz de capacidades

Leyenda: **Sí** permitido en alcance propio; **Cond.** requiere permiso específico/RPC y auditoría; **No** denegado.

| Capacidad | Propietario | Admin municipal | Supervisor | Operador | Auditor | Vecino |
|---|---:|---:|---:|---:|---:|---:|
| Ver contexto de plataforma | Sí | No | No | No | No | No |
| Ver alertas de cualquier organización | Cond. | No | No | No | No | No |
| Ver alertas de su organización | Sí | Sí | Sí | Sí | Sí | No |
| Ver detalle operativo sensible | Cond. | Cond. | Cond. | Cond. | No | No |
| Ver ficha médica | Cond. | Cond. | Cond. | Cond. | No | No |
| Cambiar estado de alerta | Cond. | Cond. | Cond. | Cond. | No | No |
| Gestionar operadores de su organización | Sí | Sí | No | No | No | No |
| Crear/asignar manzanas | Sí | Cond. | No | No | No | No |
| Cambiar organización de manzana activa | Cond. | No | No | No | No | No |
| Gestionar RBAC global | Sí | No | No | No | No | No |
| Crear alerta desde unidad propia | No | No | No | No | No | Sí |
| Recibir aviso comunitario mínimo | No | No | No | No | No | Sí |
| Ver identidad/domicilio del emisor como vecino | No | No | No | No | No | No |
| Administrar membresías de unidad | No | No | No | No | No | Cond. |

**Cond.** no significa permiso general. Cada caso requiere una RPC concreta, una regla de alcance y registro de auditoría. Para datos médicos, el permiso debe ser independiente del permiso de lectura de alerta.

## 5. Contrato de comandos

No exponer mutaciones directas a tablas privadas desde el navegador. Los nombres siguientes son contratos lógicos; no son funciones implementadas.

### Plataforma y organizaciones
- `crear_organizacion`: solo propietario activo; código único; estado inicial controlado; auditoría.
- `cambiar_estado_organizacion`: propietario; motivo obligatorio; bloqueo de operaciones si queda suspendida.
- `asignar_propietario` / `revocar_propietario`: proceso extraordinario, doble confirmación fuera de UI municipal y auditoría reforzada. Nunca invocable por admin municipal.

### Administración municipal
- `invitar_operador`: admin de la organización destino; rol objetivo permitido; invitación de un solo uso; no permite propietario ni admin de otra organización.
- `activar_membresia_municipal`: valida invitación/cuenta y registra actor.
- `cambiar_rol_municipal`: solo dentro de la organización; impide elevar a administrador salvo política explícita; nunca propietario.
- `revocar_membresia_municipal`: revoca solo esa organización y audita motivo.

### Red y unidades
- `crear_establecimiento`, `editar_establecimiento`, `cambiar_estado_establecimiento`.
- `crear_unidad`, `editar_unidad`, `habilitar_participacion_red`, `suspender_unidad`.
- `crear_invitacion_vecinal`, `solicitar_ingreso_vecinal`, `aprobar_ingreso_vecinal`, `rechazar_ingreso_vecinal`, `revocar_membresia_vecinal`.
- Las operaciones verifican titularidad/rol dentro de la unidad, estado de todos los padres y no permiten que el solicitante se apruebe a sí mismo.
- No transferir titularidad mediante UPDATE directo; requiere comando dedicado, doble verificación y auditoría.

### Alertas y COM
- `crear_alerta_vecinal_v2`: contexto de membresía válido; catálogo cerrado; idempotencia; transacción de alerta + evento + entregas.
- `listar_alertas_com_v2`: DTO explícito, alcance resuelto en servidor y paginación.
- `obtener_detalle_alerta_com_v2`: datos operativos mínimos según rol.
- `obtener_datos_medicos_alerta_v2`: permiso separado, justificación, auditoría de lectura.
- `cambiar_estado_alerta_com_v2`: transición válida, bloqueo de fila, motivo, idempotencia y auditoría.
- `listar_avisos_vecinales_v2`: solo avisos mínimos de membresías activas propias.
- Ningún vecino obtiene detalle personal del emisor.

## 6. Reglas transversales de autorización

Cada RPC debe validar en este orden, según aplique:

1. `auth.uid()` presente.
2. Perfil/cuenta no suspendidos.
3. Rol/membresía activa y organización activa.
4. Recurso objetivo existe y su alcance se deriva desde la base.
5. Recurso padre activo y relación coherente.
6. Permiso concreto para la acción y los campos afectados.
7. Límites, idempotencia, estado previo y concurrencia.
8. Auditoría dentro de la misma transacción.

No devolver errores que permitan enumerar usuarios, domicilios, unidades o alertas de otro alcance. No aceptar en el cliente `actor_id`, `rol`, `organizacion_id`, `manzana_id`, `unidad_id`, destinatarios, prioridad o estado anterior como hechos confiables.

## 7. Requisitos SQL/RLS/grants

- RLS habilitado en tablas privadas; evaluar `FORCE ROW LEVEL SECURITY` según propietarios, workers y funciones.
- Revocar grants directos que permitan saltarse RPC de comando; revisar grants por tabla y columna.
- No dar UPDATE general a `alertas` si el cambio de estado se realiza por RPC.
- Funciones `SECURITY DEFINER` con propietario mínimo, `search_path = ''`, nombres calificados, validación estricta y EXECUTE solo a roles necesarios.
- Separar funciones de usuario autenticado y funciones internas de worker.
- No exponer `service_role`, secretos Push ni claves de cifrado al navegador.
- Las políticas RLS deben evitar recursión y no depender de tablas legadas con permisos amplios.
- Realtime solo publica eventos mínimos; suscripciones no sustituyen autorización de lectura.
- Revisar vistas, funciones, triggers, secuencias, publicaciones, storage y Edge Functions como parte del mismo perímetro.

## 8. Auditoría mínima

Registrar actor Auth, tipo de actor/rol resuelto, organización/unidad alcanzada, acción, recurso, resultado, fecha, motivo y correlación/idempotencia. Evitar copiar ficha médica, tokens push, contraseñas o texto libre sensible a la auditoría.

Auditar especialmente:
- accesos globales del propietario;
- lecturas de detalle médico;
- altas, bajas y cambios de rol;
- cambio de estado de alerta;
- creación/reasignación/suspensión de manzanas, establecimientos y unidades;
- exportaciones y operaciones masivas;
- intentos denegados relevantes.

## 9. Decisiones pendientes de aprobación

1. Permisos exactos de lectura de domicilio/contacto por rol COM.
2. Si algún rol operativo podrá consultar datos médicos en emergencia y con qué justificación.
3. Proceso extraordinario y recuperación para propietario de plataforma.
4. Si una persona puede tener varios roles dentro de una misma organización o membresías en varias organizaciones.
5. Política de transferencia de titularidad de unidad.
6. Política de menores y tutores.
7. Retención diferenciada para alertas, GPS, datos médicos, entregas y auditoría.
8. Si el alcance de una manzana será siempre una sola organización; el RBAC v0.3 presupone esa cardinalidad.

Hasta resolver estos puntos, mantener denegación por defecto y no activar funciones sensibles.

## 10. Criterios de salida para pasar a SQL consolidado

- DDL real inspeccionado en proyecto aislado y comparado con los borradores.
- Una única fuente de verdad para alerta operativa.
- Relaciones FK validadas: alerta → unidad → establecimiento → manzana → organización.
- Inventario de RLS, grants, funciones SECURITY DEFINER, triggers y Realtime completado.
- Matriz de permisos aprobada y traducida a pruebas automatizadas.
- Pruebas negativas de aislamiento multi-organización y escalada de privilegios aprobadas.
- Plan de migración/rollback, datos sintéticos y backup verificados.
- Ninguna migración aplicada al Supabase compartido hasta autorización explícita.

## 11. Estado

Contrato de diseño guardado en GitHub. No se creó ni ejecutó SQL. No se modificaron datos, permisos, tablas ni despliegues. Las alertas y manzanas ficticias permanecen sin tocar.
