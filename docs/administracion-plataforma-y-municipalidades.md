# Administración de plataforma independiente y organizaciones — Alerta Vecinal Pro

Estado: diseño y migración SQL en borrador para la rama `integracion-segura-2026-11-04`.
No se ejecutó SQL en Supabase y no se modificó el acceso de producción.

## Decisión de posicionamiento y gobierno

Alerta Vecinal Pro se presenta como una **plataforma independiente**. La interfaz, los textos públicos y la consola no deben nombrar ni sugerir afiliación, respaldo o convenio con Villa Mercedes, San Luis ni otro organización mientras no exista un acuerdo formal. La arquitectura permite incorporar municipios y otras organizaciones más adelante, mediante altas controladas y aislamiento de datos. No se crea ni se asigna una municipalidad por defecto.

## Decisión de gobierno

La plataforma tendrá dos planos administrativos separados:

1. **Propietario de plataforma**: identidad nominativa del titular/desarrollador. Tiene alcance global para supervisar organizaciones, configuración, seguridad y auditoría. Su alta inicial se realiza exclusivamente por un administrador de base de datos mediante un procedimiento controlado; ningún administrador municipal puede crearlo, modificarlo ni revocarlo.
2. **Administración de organización**: cuando se incorpore un municipio u otra entidad mediante un acuerdo formal, su administrador gestiona sus propios operadores, roles y bajas. Sus permisos se limitan a su organización. No puede gestionar otras organizaciones, propietarios de plataforma ni configuración global.

No se comparte una cuenta entre funcionarios. Cada persona utiliza una identidad propia de Supabase Auth y sus sesiones/MFA individuales.

## Roles iniciales

| Rol | Alcance | Capacidades |
|---|---|---|
| propietario_plataforma | Global | Supervisión global y administración de organizaciones, seguridad y auditoría |
| administrador_municipal | Una organización | Alta/invitación, suspensión y baja lógica de operadores de su municipio; asignación de roles municipales |
| supervisor_municipal | Una organización/área autorizada | Supervisión de alertas e informes |
| operador_municipal | Manzanas asignadas a su organización | Gestión operativa de alertas autorizadas |
| auditor_municipal | Una organización | Lectura de auditoría e informes autorizados |

Los roles se almacenan en el servidor. Nunca se aceptan como autoridad valores enviados por el navegador, metadatos editables del usuario ni el correo por sí solo.

## Identidad y autorización

- Supabase Auth autentica la identidad; las tablas privadas de autorización deciden qué puede hacer.
- La tabla `propietarios_plataforma` contiene identidades explícitamente elevadas. No se eleva a nadie por coincidencia de correo ni por registrarse.
- `membresias_municipales` relaciona `auth.users.id` con una organización y un rol municipal.
- La membresía debe estar activa para autorizar operaciones.
- Las funciones privilegiadas futuras deben ser RPC SECURITY DEFINER con `SET search_path = ''`, objetos calificados por esquema, validación de `auth.uid()`, organización y rol; EXECUTE revocado de PUBLIC/anon y concedido solo a authenticated cuando corresponda.
- La invitación/creación de cuentas debe realizarse en servidor confiable usando Supabase Auth Admin API. La clave service_role nunca se incluye en HTML ni en el navegador.
- Preferir invitación por correo y establecimiento de contraseña por el funcionario; nunca enviar ni almacenar contraseñas propias.
- Activar MFA para perfiles administrativos y definir recuperación, expiración de sesión y revocación.
- Las bajas son lógicas y revocan membresía/sesiones según el procedimiento; conservar auditoría.
- El administrador municipal no puede alterar la fila de propietario ni crear propietarios.
- Registrar actor, organización, acción, objetivo y fecha; no guardar contraseñas, tokens, PIN ni ficha médica en la auditoría.

## Compatibilidad con el sistema actual

- La tabla existente `operadores(email)` y la función `es_operador()` son legado utilizado por las políticas actuales del COM.
- No se elimina ni modifica esa tabla o función en esta fase.
- Los correos actualmente listados en `operadores` NO se convierten automáticamente en propietarios ni administradores municipales. Su identidad y autorización deben verificarse y migrarse mediante un proceso explícito.
- La migración propuesta agrega el catálogo de organizaciones y membresías, y una relación opcional de manzanas con organización. No asigna automáticamente manzanas ni usuarios.
- Mientras las políticas actuales sigan usando `es_operador()`, el alcance municipal por organización NO está aplicado. La migración de datos y sustitución de políticas/RPC actuales es una fase posterior obligatoria antes de habilitar varios municipios.
- Los datos existentes de manzanas y alertas son ficticios de prueba. No deben presentarse como residentes, domicilios ni emergencias reales.

## Fases de implementación

1. **Catálogo RBAC**: crear tablas privadas y predicados de rol; sin asignar usuarios ni alterar los RPC existentes.
2. **Bootstrap del propietario**: verificar identidad Auth del titular y registrar su UUID manualmente por canal administrativo seguro. Nunca colocar correo o contraseña en el SQL público.
3. **Organización municipal**: crear la organización y asociar manzanas autorizadas.
4. **Invitaciones y gestión**: implementar Edge Function/backend confiable con Auth Admin API para invitar usuarios; RPCs de asignación, suspensión y revocación.
5. **Aislamiento por organización**: reemplazar cuidadosamente políticas globales heredadas por políticas/RPC que comprueben organización y rol. Probar que un municipio no puede consultar ni alterar otro.
6. **Interfaz COM**: mostrar panel de gestión de operadores solo al administrador municipal; mostrar vista global al propietario.
7. **Pruebas**: propietario, dos municipios aislados, administrador, supervisor, operador, auditor, usuario sin rol, sesión revocada y usuario desactivado.

## Criterios de aceptación

- El propietario ve el alcance global y nunca puede ser administrado por un municipio.
- Un administrador municipal puede gestionar operadores únicamente de su organización.
- Un operador de un municipio no puede leer ni modificar recursos de otro.
- Autenticarse no equivale a estar autorizado.
- Ninguna cuenta administrativa se comparte ni se aprovisiona con una contraseña conocida por el desarrollador.
- Las operaciones administrativas quedan auditadas.
- El COM existente continúa funcionando durante la transición; no se cambia la autenticación vigente hasta que las nuevas RPC y políticas estén probadas.
- No se declara multi-municipio seguro hasta completar el aislamiento de datos en RLS/RPC.

## Estado real

Este documento y el SQL asociado son especificación/borrador. No se crearon cuentas, no se enviaron invitaciones, no se ejecutó migración y no se cambió Supabase ni producción.


## Implementación preparada en la rama (04-11-2026)

- `administracion.html`: acceso autenticado para propietario y administradores municipales, selector de organización, alta de organización exclusiva del propietario, invitación de operadores, activación después de confirmar correo, cambio de rol y revocación de membresías.
- `supabase/functions/administrar-operadores/index.ts`: valida JWT, contexto RBAC y alcance organizacional; usa Auth Admin API solo en servidor; aplica límite de 10 invitaciones por hora por actor; protege la identidad propietaria y deja membresías nuevas en estado pendiente hasta confirmar correo.
- `supabase/config.toml`: exige verificación JWT para la Edge Function.
- `admin.html`: ya no muestra el COM a cualquier sesión autenticada; exige que la función heredada `es_operador()` autorice el acceso. El PIN de cada manzana queda oculto en la tabla.
- `index.html`: agrega acceso a la administración institucional, que exige sesión y rol autorizado.

Estos componentes requieren aplicar las migraciones RBAC v0.1 y v0.2 y desplegar la Edge Function en un proyecto de pruebas. No se crearon cuentas ni invitaciones. El COM operativo aún conserva las políticas heredadas; el aislamiento multi-municipal de alertas y manzanas sigue siendo una fase pendiente y obligatoria.


## Aislamiento de datos y consola (borrador v0.3)

Se agregó `docs/migracion-rbac-plataforma-municipios-v0.3-borrador.sql`. Retira las políticas heredadas globales `op_alertas_select`, `op_alertas_update` y `op_manzanas_all`, y propone políticas por organización:
- Propietario: lectura global de alertas/manzanas y gestión global permitida.
- Administrador municipal: lectura/gestión de manzanas de su organización y gestión operativa de alertas propias.
- Supervisor: lectura y actualización operativa de alertas propias.
- Operador: lectura y actualización operativa de alertas propias.
- Auditor: solo lectura de alertas/manzanas propias.

La consola COM consulta el contexto RBAC, filtra por RLS, oculta acciones de escritura a auditores y asocia cada manzana nueva a una organización. Las manzanas/alertas ficticias existentes no se asignan automáticamente a ningún municipio.

La política de alertas enlaza temporalmente por `alertas.manzana = manzanas.nombre_manzana`; antes de escalar a múltiples municipios se debe migrar a una FK `alertas.manzana_id` y validar que el nombre siga siendo único globalmente.

## Advertencia de transición

La compatibilidad con `es_operador()` solo se usa si la RPC nueva `obtener_contexto_administrativo()` todavía no existe (entorno previo a migraciones). Una vez instalada la nueva arquitectura, una cuenta presente únicamente en `public.operadores` ya no obtiene acceso: debe recibir una membresía municipal explícita. No convertir automáticamente los dos correos heredados.
