# VIGIARED — Plan de cierre, integración y pruebas

Estado: plan de trabajo para la rama `integracion-segura-2026-11-04`.
Objetivo: completar la plataforma en desarrollo, probarla con un entorno de datos aislado y promover a producción únicamente después de aprobar todos los criterios de salida.

## Regla de publicación

- No fusionar esta rama a `main` ni asignar el dominio de producción durante el desarrollo.
- No ejecutar migraciones experimentales en el proyecto Supabase actualmente conectado.
- Las manzanas y alertas existentes son datos ficticios de prueba; no representan domicilios, personas ni emergencias reales.
- La vista previa de Vercel utiliza el proyecto Supabase existente. Por eso no se deben ejecutar allí pruebas que inserten alertas, cambien estados, creen manzanas o modifiquen cuentas.
- Las pruebas de escritura requieren un proyecto Supabase aislado con datos sintéticos, cuentas de prueba y claves independientes.
- No habilitar vecinos, comercios ni organizaciones reales hasta completar pruebas funcionales, de autorización, privacidad y recuperación.

## Hallazgos de la revisión del código

### 1. Acceso vecinal — incompleto

La terminal vecinal de la rama de desarrollo fue reemplazada por una pantalla de identidad individual VIGIARED. Es actualmente un **andamio visual**: los controles de registro, ingreso, invitación y solicitud permanecen deshabilitados; no inicializa Supabase, no autentica usuarios y no envía alertas. El flujo anterior de manzana/PIN y las llamadas RPC heredadas fueron retirados de esa pantalla.

Falta implementar antes de considerarlo acceso vecinal seguro:

- Registro y autenticación individual de cada integrante.
- Relación validada en servidor entre cuenta, domicilio, unidad habitacional y manzana.
- Aprobación del alta por una persona autorizada.
- Revocación individual sin afectar a los demás integrantes del domicilio.
- Límite de intentos, bloqueo temporal y auditoría de credenciales.
- Separación de vivienda, departamento, habitación, hostel, comercio y otras unidades independientes.
- Reglas de consentimiento y minimización de datos; ficha médica solo con acceso operativo estrictamente autorizado.

El PIN de manzana no debe convertirse en una credencial permanente ni ser el único control de pertenencia.

### 2. Alertas y distribución comunitaria — incompleto

El Centro de Operaciones conserva la consulta de `public.alertas` y la escucha de inserciones de Realtime. La terminal vecinal actual no crea alertas: el envío permanece deshabilitado hasta que se implemente y pruebe la identidad individual y la RPC segura.

Falta implementar y verificar:

- Resolver la identidad y unidad desde una credencial validada en servidor; no confiar en identidad/domicilio enviados por el navegador.
- Vincular cada alerta a `manzana_id`, unidad e integrante mediante claves foráneas; no depender a largo plazo del nombre de manzana como texto.
- Entrega de aviso anónimo a los integrantes activos y autorizados de la misma comunidad.
- Preferencias de recepción, consentimiento, baja y revocación.
- Confirmación técnica de recepción, reintentos y trazabilidad sin duplicar alertas.
- Notificación con la aplicación cerrada mediante Web Push/FCM; Realtime solo cubre clientes conectados.
- Tratamiento de GPS denegado, dirección incompleta, pérdida de conectividad y reenvío seguro.

El mensaje comunitario no debe revelar nombre, teléfono, dirección exacta ni ficha médica del emisor.

### 3. Centro de Operaciones — base existente, requiere integración

El COM ya contiene listado, filtros, estados, datos de domicilio, enlace de mapa, suscripción Realtime y activación manual de sonido.

Pendiente de validar y completar:

- Alcance de datos impuesto por RLS, nunca solo por ocultar controles en pantalla.
- Identificación inequívoca de organización y manzana de cada alerta.
- Revisión de transiciones de estado y registro de auditoría.
- Sonido al recibir nuevas alertas, control de duplicados y comportamiento con pestaña en segundo plano.
- Mapa y domicilio exacto; distinguir ubicación GPS del dispositivo y domicilio declarado.
- Estados de conexión y reconexión de Realtime.
- Operador auditor en modo de solo lectura.

### 4. Organizaciones y permisos — código preliminar, no habilitado

Existen borradores RBAC v0.1, v0.2 y v0.3, una pantalla administrativa y una Edge Function para operadores. No están aplicados ni desplegados.

Antes de activarlos:

- Revisar las migraciones en conjunto y probarlas en una base aislada.
- Confirmar que el propietario de plataforma tenga control global.
- Confirmar que cada administrador solo gestione su organización.
- Confirmar que supervisor/operador/auditor tengan permisos mínimos.
- Comprobar que un usuario sin membresía no lea ni modifique datos.
- Eliminar cualquier vía heredada que permita acceso global por estar listado en `public.operadores`.
- Desplegar la Edge Function solo después de verificar esquema, secretos y autorización.
- Crear al propietario solo mediante el procedimiento explícito con una cuenta Auth ya confirmada; nunca inferir correo ni crear un propietario automáticamente.

La consola dejó de usar el fallback heredado `es_operador()`: si no puede obtener el contexto RBAC, deniega el acceso. Esto es deliberadamente fail-closed; la consola no funcionará para operadores antiguos hasta completar la migración y asignar membresías RBAC.

### 5. Comercios — no cerrar como funcional todavía

La arquitectura contempla comercios y empleados, pero deben completarse altas, unidades/sucursales, usuarios individuales, revocación, alertas y aislamiento respecto de vecinos y otras organizaciones.

### 6. Identidad y documentación

- Marca de producto: VIGIARED.
- Lema: “Tecnología que conecta y protege”.
- Plataforma independiente; no sugerir convenio, aval ni afiliación municipal inexistente.
- Mantener Rastreo Urbano GPS como desarrollador/identidad comercial donde corresponda.
- No asociar Educa 360 como titular o responsable sin decisión expresa.
- La disponibilidad legal de la marca sigue pendiente de búsqueda y evaluación formal.

## Secuencia de implementación

1. Cerrar modelo de datos de organizaciones, manzanas, establecimientos, unidades e integrantes.
2. Implementar RPC seguras de alta, aprobación, autenticación, revocación y resolución de identidad.
3. Adaptar la terminal vecinal a credenciales individuales y unidades habitacionales.
4. Implementar la alerta segura con vínculo relacional a la unidad y organización.
5. Implementar difusión comunitaria anónima y notificaciones en segundo plano.
6. Completar COM: alcance RBAC, mapa, estados, auditoría, sonido y reconexión.
7. Completar gestión de organizaciones, administradores y operadores mediante Edge Function.
8. Completar comercios y sus empleados con aislamiento propio.
9. Preparar entorno aislado de QA y ejecutar las pruebas siguientes.
10. Corregir hallazgos, repetir regresión y obtener aprobación antes de producción.

## Matriz mínima de pruebas de aceptación

| Área | Prueba | Resultado requerido |
|---|---|---|
| Identidad | Usuario sin sesión intenta entrar al COM | Acceso denegado |
| RBAC | Usuario autenticado sin membresía | No lee ni modifica datos |
| Aislamiento | Admin A consulta datos de organización B | Cero filas y ninguna mutación |
| RBAC | Auditor intenta cambiar estado | Operación denegada |
| RBAC | Operador intenta crear organización | Operación denegada |
| Propietario | Propietario consulta organizaciones autorizadas | Vista global disponible |
| Vecinos | Dos integrantes del mismo domicilio | Cuentas individuales independientes |
| Vecinos | Revocar un integrante | Los demás conservan acceso |
| Vecinos | Unidad/departamento distinto | No recibe alertas privadas de otra unidad |
| QR | Escanear QR público | Abre terminal sin PIN ni secreto en URL |
| Alertas | Envío autorizado | Una alerta registrada con identidad resuelta por servidor |
| Alertas | Envío repetido o doble clic | No duplica una misma operación |
| Comunidad | Alerta de manzana | Aviso anónimo solo a participantes activos de esa manzana |
| Privacidad | Inspeccionar aviso comunitario | No expone identidad, teléfono, domicilio exacto ni ficha médica |
| COM | Alerta nueva | Aparece una vez, con domicilio y ubicación diferenciados |
| COM | Operador activa sonido | Tono de prueba audible y nuevas alertas audibles |
| COM | Cambiar estado | Solo roles autorizados; queda auditoría |
| Push | Aplicación cerrada | Notificación recibida en dispositivo suscripto |
| Revocación | Revocar credencial/dispositivo | Acceso futuro rechazado |
| Comercios | Empleado de comercio A consulta comercio B | Acceso denegado |
| Resiliencia | Sin GPS / sin red / reconexión | Mensaje claro; no confirma entrega no realizada |
| Regresión | Recorrer todos los roles y módulos | Sin errores bloqueantes ni filtraciones |

## Criterios para autorizar producción

Todos deben cumplirse:

- [ ] Migraciones aprobadas y ejecutadas en el entorno correcto después de backup y ensayo aislado.
- [ ] RLS verificada con cuentas de cada rol y pruebas negativas entre organizaciones.
- [ ] Credenciales vecinales individuales y revocables funcionando.
- [ ] Alertas y difusión comunitaria probadas de extremo a extremo.
- [ ] Push probado con aplicación cerrada.
- [ ] COM probado en escritorio y móvil, incluyendo sonido y mapa.
- [ ] Comercios y organizaciones aislados y probados.
- [ ] Edge Functions y secretos configurados sin claves privilegiadas en el navegador.
- [ ] Pruebas de regresión aprobadas y hallazgos críticos resueltos.
- [ ] Copia de seguridad, plan de reversión y aprobación expresa de publicación.


## Avance de identidad vecinal v0.2 (2026-11-04)

Se incorporó el borrador `docs/migracion-identidad-vecinal-v0.2-borrador.sql` y su documentación. El modelo separa cuenta Auth, perfil único y membresías por unidad; una misma persona puede pertenecer a múltiples unidades. Las RPC de provisionamiento y bootstrap se reservan a `service_role`; las RPC de usuario se limitan a `authenticated`. Las tablas nuevas mantienen RLS y no conceden acceso directo.

Los borradores v0.1 de identidad, invitación y aprobación quedaron marcados como supersedidos. Se agregó una revisión estática en `docs/revision-seguridad-identidad-vecinal-v0.2.md`. Se corrigieron hallazgos de sintaxis y controles de perfil/autoaprobación durante la revisión.

**Límite actual:** no se ejecutó ni compiló el SQL en PostgreSQL; no existe todavía un proyecto Supabase aislado. No conectar las RPC a la terminal. Tampoco hay un runner de pruebas de aplicación identificado en la raíz del repositorio (no se encontró `package.json`). El siguiente paso es preparar un entorno aislado y probar migración, permisos y concurrencia antes de integrar frontend.

### Avance de pruebas de identidad v0.2

Se incorporó `docs/pruebas-identidad-vecinal-v0.2.md` con 28 casos funcionales, 7 escenarios de concurrencia y 8 verificaciones de privilegios/SECURITY DEFINER. La revisión estática también reforzó el canje para unidades activas y el rechazo por titulares con perfil activo.

**Estado:** casos documentados, no ejecutados. Sigue bloqueado cualquier ensayo de escritura hasta contar con proyecto Supabase aislado. La Preview actual comparte la base existente.


### Revisión de alertas y COM v0.2 (2026-11-04)

Se incorporó `docs/revision-alertas-com-v0.2.md` con auditoría estática del COM y diseño de autorización/difusión. Hallazgos relevantes:

- `admin.html` consulta `alertas` mediante `select('*')`; el filtrado posterior ocurre en el navegador y no constituye aislamiento.
- La gestión heredada consulta `manzanas` con `select('*')` y todavía crea manzanas mediante INSERT directo desde el cliente, con PIN compartido.
- La verificación RBAC al iniciar sesión falla cerrado, pero por sí sola no protege lecturas y escrituras posteriores. El aislamiento debe aplicarse en RLS/RPC.
- Las alertas nuevas deben derivar usuario, unidad, manzana y organización desde la sesión y las membresías verificadas en servidor. Nunca aceptar destinos o listas de destinatarios arbitrarios del cliente.
- COM y red vecinal requieren canales distintos: el aviso vecinal no incluye identidad, domicilio exacto, contacto, GPS, ficha médica ni texto libre.
- Se definieron 26 casos de prueba para creación, autorización, privacidad, outbox, concurrencia, push y COM.

**Estado:** auditoría y requisitos documentados; no se modificó el flujo de alertas, no se creó una RPC/worker y no se ejecutó SQL. La pestaña de manzanas y la consulta de alertas deben considerarse heredadas/no listas para habilitar usuarios reales hasta que el backend imponga el alcance por organización.


### Diseño backend de alertas v0.2 (2026-11-04)

Se agregó `docs/diseno-backend-alertas-v0.2.md`, especificación previa al SQL con:
- Contrato de creación autenticada e idempotente; contexto y destinatarios derivados del servidor.
- Transacción única para alerta, difusión, entregas y auditoría.
- Outbox durable con lease, `SKIP LOCKED`, revalidación de membresía y reintentos.
- DTOs COM acotados por organización, detalle sensible separado y transiciones de estado auditadas.
- Privilegios/RLS, antiabuso, privacidad de ubicación y separación de datos médicos.
- 14 pruebas adicionales AL-27 a AL-40.

**Bloqueo detectado:** el borrador de red relaciona establecimientos con manzanas, mientras el RBAC requiere una relación canónica manzana-organización. Debe verificarse cardinalidad y fuente de verdad antes del SQL final. También debe decidirse si se conserva `public.alertas` como almacenamiento operativo o se migra a una tabla privada nueva; no se crearán dos fuentes de verdad.

**Estado:** solo diseño y documentación. Sin DDL nuevo, sin cambios de frontend, sin SQL ejecutado, sin worker desplegado y sin notificaciones activadas.


**Aclaración de arquitectura:** la revisión de RBAC v0.3 permitió identificar que la relación prevista es `manzanas.organizacion_id` (una organización por manzana). Se actualizó el diseño v0.2 para derivar el alcance mediante `unidades → establecimientos → manzanas`, sin duplicar la organización en tablas hijas. Sigue pendiente verificar esa columna en un esquema aislado, porque el RBAC v0.3 también es un borrador y no prueba el estado de la base compartida.


### Auditoría de coherencia RBAC + red comunitaria

Se creó `docs/auditoria-coherencia-rbac-red-v0.1.md` tras revisar RBAC v0.1–v0.3, bootstrap del propietario y red comunitaria v0.1.

Hallazgos que bloquean el SQL integral:
- La política UPDATE por fila de alertas no limita columnas; se recomienda quitar UPDATE directo y usar RPC de transición auditada.
- Las políticas actuales permiten escrituras directas sobre manzanas; se recomienda reemplazarlas por comandos RPC auditados.
- El vínculo histórico `alertas.manzana` por texto es temporal; la nueva autoridad debe ser unidad de origen y relaciones persistidas.
- Deben inventariarse grants efectivos, privilegios por columna, funciones SECURITY DEFINER, triggers, vistas y RLS antes de consolidar.
- La matriz de permisos COM se explicitó para propietario, administrador, supervisor, operador y auditor.
- Se reafirma que `vecinos` legado no es fuente de autorización y que no se deben emparejar datos ficticios.

**Decisión técnica:** no escribir ni ejecutar todavía un SQL integral. Primero consolidar el contrato de permisos y verificar el DDL/privilegios reales en un Supabase desechable. No se modificó el proyecto Supabase compartido.


### Contrato único de permisos y operaciones v0.1

Se creó `docs/contrato-unico-permisos-operaciones-v0.1.md`. Consolida las fuentes de autoridad, la separación propietario/municipio/vecindario, la matriz de capacidades, los comandos lógicos por dominio, requisitos RLS/grants, auditoría y criterios de salida para SQL consolidado.

**Regla reforzada:** no conceder UPDATE directo general a `alertas`; las transiciones serán RPC con campos permitidos, validación de estado, concurrencia y auditoría atómica. Las altas/modificaciones de manzanas, establecimientos y unidades también serán comandos de servidor, no INSERT/UPDATE libre desde navegador.

Quedan marcadas decisiones de producto que requieren aprobación antes de abrir funciones sensibles: datos personales visibles por rol COM, acceso excepcional a datos médicos, recuperación/transferencia del propietario, titularidad de unidad, menores/tutores, retención y cardinalidad de manzana-organización.

**Estado:** documento guardado; no se ejecutó SQL ni se modificó Supabase o producción.


### Bloqueo de compatibilidad de esquema — inventario v0.1

Se agregó `docs/inventario-compatibilidad-esquema-v0.1.md` (commit `eb237b7a171cee340d79ec258d71735a42da0eaf`). Antes de consolidar SQL:
- Incorporar `alertas.unidad_id` como origen canónico derivado de la membresía autenticada.
- No duplicar `manzana_id` en difusiones; derivar el alcance por FK.
- Eliminar el join temporal por nombre entre `alertas` y `manzanas`.
- No usar `vecinos` ni `credenciales_integrantes` como autoridad de identidad.
- Resolver fuente única de alertas y verificar tipo real de IDs, timestamps, estados y dependencias.
- Inspeccionar DDL en un Supabase aislado antes de preparar una migración ejecutable.

Sin SQL ejecutado, sin cambios en Supabase y sin alteración de alertas/manzanas ficticias.
