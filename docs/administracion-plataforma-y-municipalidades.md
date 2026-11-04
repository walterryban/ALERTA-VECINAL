# Administración de plataforma y municipalidades — Alerta Vecinal Pro

Estado: diseño y migración SQL en borrador para la rama `integracion-segura-2026-11-04`.
No se ejecutó SQL en Supabase y no se modificó el acceso de producción.

## Decisión de gobierno

La plataforma tendrá dos planos administrativos separados:

1. **Propietario de plataforma**: identidad nominativa del titular/desarrollador. Tiene alcance global para supervisar organizaciones, configuración, seguridad y auditoría. Su alta inicial se realiza exclusivamente por un administrador de base de datos mediante un procedimiento controlado; ningún administrador municipal puede crearlo, modificarlo ni revocarlo.
2. **Administración municipal**: cada municipio administra sus propios operadores, roles y bajas. Sus permisos se limitan a su organización. No puede gestionar otros municipios, propietarios de plataforma ni configuración global.

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
