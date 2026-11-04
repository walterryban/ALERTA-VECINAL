# VIGIARED — Auditoría de coherencia RBAC v0.3 y red comunitaria v0.1

**Estado:** revisión estática de borradores; no valida el estado real de Supabase.  
**No ejecutar:** este documento no es una migración.  
**Rama:** `integracion-segura-2026-11-04`

## 1. Resultado ejecutivo

Los borradores ya expresan una separación útil: propietario global de plataforma, miembros municipales limitados a una organización y una jerarquía física manzana → establecimiento → unidad. Sin embargo, todavía no constituyen un control de acceso completo ni deben aplicarse como paquete.

El principal riesgo no es la ausencia de roles en la interfaz, sino que las políticas RLS y permisos SQL no reducen por sí solos el alcance de columnas ni garantizan que cada comando operativo tenga una autorización transaccional específica.

## 2. Hallazgos prioritarios

### RBAC-01 — UPDATE de fila no limita columnas

La política `rbac_alertas_update` del borrador RBAC v0.3 autoriza UPDATE por fila para propietario y ciertos roles municipales. Una política RLS UPDATE no decide qué columnas pueden cambiarse. Si el rol SQL tiene UPDATE sobre la tabla, un operador podría intentar modificar campos que no forman parte de la operación cotidiana, según los grants efectivos.

**Corrección de diseño:** retirar UPDATE directo a `authenticated` en `alertas` y ofrecer RPC de transición de estado con lista explícita de campos, validación de estado anterior/nuevo, motivo, permiso, bloqueo de fila e inserción de auditoría en la misma transacción. No otorgar escritura general para resolver un cambio de estado.

### RBAC-02 — El propietario global y el administrador municipal necesitan comandos distintos

El predicado `es_propietario_plataforma()` da alcance global y `tiene_rol_municipal()` verifica una organización. Es correcto mantenerlos separados. Pero las futuras RPC deben validar explícitamente cuál de esos caminos se está usando y no aceptar `organizacion_id` del navegador como autoridad.

**Corrección de diseño:** para recursos municipales, resolver la organización desde la fila objetivo. El propietario puede actuar globalmente bajo auditoría; el administrador municipal solo dentro de su organización. La gestión de operadores no debe conceder nunca rol de propietario.

### RBAC-03 — La relación por texto de alerta es temporal

RBAC v0.3 asocia alertas a manzanas por `alertas.manzana = manzanas.nombre_manzana`. El comentario ya reconoce que esto depende de unicidad global del nombre. Es una relación frágil y no sirve como contrato definitivo de integridad.

**Corrección de diseño:** usar FK `alertas.manzana_id` o, preferentemente para nuevas alertas, guardar `unidad_id` de origen y derivar manzana/organización mediante las relaciones. La migración de históricos debe ser explícita, revisada y nunca inferir asociaciones para datos ficticios.

### RBAC-04 — Los grants efectivos no están consolidados en los borradores

RBAC v0.3 crea políticas y elimina algunas políticas heredadas, pero la seguridad efectiva también depende de GRANT/REVOKE, RLS FORCE cuando corresponda, propietario de funciones, privilegios heredados y funciones `SECURITY DEFINER` existentes. La política no demuestra por sí sola que el navegador carezca de permisos amplios.

**Corrección de diseño:** inventario de privilegios por tabla, columna, secuencia y función; revocar escrituras directas que se sustituyan por RPC. Verificar explícitamente el comportamiento de tablas consultadas desde políticas y funciones con RLS activado.

### RBAC-05 — Gestión de manzanas necesita RPC y auditoría

La política v0.3 permite INSERT/UPDATE directo a propietario o administrador municipal en `manzanas`. El diseño del COM actual todavía inserta directamente desde navegador. Esto hace difícil garantizar auditoría, validar organización activa y evitar cambios de organización o reasignaciones no autorizadas en un único comando de negocio.

**Corrección de diseño:** RPC separadas para crear, editar datos descriptivos, asignar y dar de baja lógicamente una manzana. La RPC valida la organización, registra actor/antes/después y no permite cambiar la organización de una manzana ya operativa sin un proceso especial.

### RBAC-06 — El catálogo de organizaciones y membresías no tiene ciclo de vida completo

RBAC v0.1 define organizaciones y membresías, pero no implementa todo el flujo de alta, invitación, revocación, recuperación y auditoría de cambios de rol. RBAC v0.2 agrega una auditoría y funciones de contexto/gestión, pero no completa por sí solo las operaciones.

**Corrección de diseño:** toda alta/baja/cambio de rol debe ser RPC atómica y auditada. La cuenta municipal no se crea por insertar un correo ni por figurar en la tabla heredada `operadores`. No migrar automáticamente operadores históricos.

### RED-01 — Los estados de red deben bloquear operaciones en todos los niveles

El borrador de red permite estados `pendiente`, `activo`, `suspendido`, `inactivo` en establecimientos y unidades. La autorización de alertas debe comprobar además que la manzana está asignada a una organización activa. La pertenencia a una manzana no implica automáticamente participación: `unidades.participa_red` debe ser verdadera.

**Corrección de diseño:** una alerta solo se origina en una unidad activa, de establecimiento activo, con participación habilitada y manzana asignada a organización activa. La audiencia se limita a unidades elegibles dentro de ese mismo alcance.

### RED-02 — El vínculo opcional de vecinos legados no debe convertirse en autorización

La columna `vecinos.unidad_id` del borrador de red es nullable y los datos históricos/ficticios no deben vincularse por nombre, teléfono o domicilio. La identidad v0.2 correctamente reemplaza esa tabla como fuente de autorización.

**Corrección de diseño:** `perfiles_vecinales` y `membresias_vecinales` son la autoridad. `public.vecinos` permanece legado hasta un plan separado de archivo/retención. No hacer joins de coincidencia automática.

### RED-03 — Riesgo de doble fuente de verdad para alertas

El esquema actual y RBAC v0.3 operan sobre `public.alertas`, mientras que la nueva identidad usa unidades y membresías, y el diseño de difusión v0.1 añade una columna `manzana_id`. No está decidido si `public.alertas` se mantiene como tabla operativa privada o si se crea una nueva tabla.

**Corrección de diseño:** elegir una única fuente operativa. Para compatibilidad, podría conservarse `public.alertas` con FK `unidad_id` y una migración versionada, pero solo después de comprobar sus tipos, constraints, triggers, grants y dependencias reales. No desplegar simultáneamente dos almacenes de alertas.

## 3. Contrato de permisos recomendado

| Actor | Leer alertas | Cambiar estado | Gestionar usuarios municipales | Ver ficha médica |
|---|---|---|---|---|
| Propietario plataforma | Global, auditado | Según permiso global explícito | Global | No por defecto; permiso específico |
| Administrador municipal | Solo su organización | Según matriz aprobada | Solo su organización, excepto crear propietario | No por defecto |
| Supervisor municipal | Solo su organización | Según matriz aprobada | No, salvo delegación limitada futura | No por defecto |
| Operador municipal | Solo su organización | Solo comandos asignados | No | No por defecto |
| Auditor municipal | Solo su organización | No | No | No por defecto |
| Vecino | Avisos comunitarios mínimos de su red | No | No | Nunca datos de terceros |

La matriz es una propuesta conservadora. La autorización final se aplica en servidor, no mediante ocultar controles.

## 4. Orden de consolidación recomendado

1. Inventariar esquema real y privilegios en un proyecto aislado.
2. Consolidar RBAC v0.1–v0.3 en una sola migración limpia, sin ejecutar scripts históricos uno por uno.
3. Sustituir acceso directo de COM a `alertas` y `manzanas` por RPCs de lectura y comandos.
4. Establecer relación canónica de alerta a unidad y de manzana a organización.
5. Consolidar red + identidad + alertas + difusión evitando referencias al modelo legado como autoridad.
6. Probar aislamiento entre organizaciones, roles, privilegios, columnas, concurrencia y auditoría.
7. Solo después conectar COM y terminal.

## 5. Verificaciones que faltan y no se deben simular

- DDL real de `manzanas`, `alertas`, `vecinos`, `operadores` y funciones heredadas.
- Grants efectivos de tabla/columna/secuencia/función y membresías de roles.
- Políticas RLS existentes y si RLS está forzado donde corresponde.
- Propietario y configuración de todas las funciones `SECURITY DEFINER`.
- Triggers, vistas, publicaciones Realtime y dependencias del frontend.
- Tipos reales de IDs y restricciones de unicidad.
- Confirmación de que ningún borrador previo fue aplicado en el proyecto compartido.

## 6. Conclusión

No se recomienda escribir todavía una migración SQL integral de alertas. Primero hay que convertir los borradores RBAC y red en un contrato único de permisos y comandos, y comprobar el esquema real en un entorno desechable. Este orden evita que una RPC nueva quede anulada por grants heredados o que una política de fila permita modificar campos sensibles.

**Estado de ejecución:** no se ejecutó SQL, no se modificó Supabase, no se desplegó Edge Function y no se tocaron datos ficticios.
