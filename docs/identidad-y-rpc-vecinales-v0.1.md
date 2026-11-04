# VIGIARED — Identidad y RPC vecinales v0.1

Estado: especificación de diseño; no implementada ni probada contra Supabase.
Dependencia de datos: `docs/migracion-red-comunitaria-v0.1-borrador.sql`.
Migración asociada: `docs/migracion-identidad-vecinal-v0.1-borrador.sql`.

## Decisión de arquitectura

- Una persona inicia sesión con su propia cuenta Supabase Auth. No se comparte un usuario ni un PIN familiar.
- Una membresía vincula esa cuenta, una persona registrada y una unidad concreta.
- Una unidad puede tener múltiples integrantes, sin límite artificial por cantidad de familiares o residentes.
- Un establecimiento puede contener varias unidades independientes: departamentos, habitaciones, locales u oficinas.
- El QR público identifica como máximo el establecimiento/unidad de destino. Nunca transporta PIN, token ni credencial.
- El código de invitación es aleatorio, de un solo uso, con vencimiento; se guarda únicamente su hash.
- Canjear una invitación crea una solicitud pendiente. No concede acceso operativo hasta la aprobación.
- Revocar una membresía bloquea a esa cuenta para esa unidad sin afectar a los demás integrantes.
- Los permisos se comprueban en servidor en cada operación; ocultar botones en la interfaz no es control de seguridad.

## Ciclo de alta

1. Un titular autorizado emite una invitación para una unidad.
2. El servidor genera un token aleatorio de alta entropía, guarda solo su hash y devuelve el token una sola vez.
3. La persona crea/inicia sesión con su cuenta individual.
4. Canjea el token; la RPC valida hash, vencimiento, revocación y uso bajo bloqueo transaccional.
5. Se crea o vincula la ficha de integrante y una membresía en estado pendiente.
6. El titular/administrador autorizado revisa y aprueba.
7. Solo una membresía activa permite acceder a funciones de esa unidad.
8. La revocación se registra con actor, fecha y motivo; no elimina el historial.

## Contrato de RPC pendiente

| RPC | Quién puede ejecutarla | Efecto |
|---|---|---|
| `emitir_invitacion_vecinal` | Titular autorizado de la unidad | Emite invitación de un solo uso |
| `solicitar_ingreso_vecinal` | Usuario Auth autenticado | Canjea invitación y crea solicitud pendiente |
| `aprobar_membresia_vecinal` | Titular/administrador autorizado | Activa membresía tras revisión |
| `revocar_membresia_vecinal` | Titular/administrador autorizado | Revoca solo esa membresía |
| `mi_contexto_vecinal` | Usuario Auth autenticado | Devuelve únicamente sus membresías y unidades |

Las funciones deberán usar `SECURITY DEFINER`, `SET search_path = ''`, referencias totalmente calificadas, autorización explícita basada en `auth.uid()`, validación de estado y concesiones `EXECUTE` mínimas. Ninguna función aceptará como autoridad un `auth_user_id` enviado por el navegador.

## Reglas de seguridad y privacidad

- No confiar en nombre, teléfono, domicilio, unidad, manzana o rol declarados por el cliente para decidir autorización.
- No permitir que el usuario se autoapruebe, se convierta en titular o cambie el estado de su membresía.
- No devolver hashes de invitación ni tokens almacenados.
- Aplicar límites de intentos y respuestas que no permitan enumerar domicilios o integrantes.
- No enviar datos personales ni ficha médica en la difusión comunitaria.
- Un integrante de una unidad no accede por defecto a otra unidad del mismo establecimiento.
- La tutela de menores debe modelarse expresamente y no inferirse por compartir domicilio.
- Las cuentas de empleados de comercios deben usar un modelo/rol separado; no reutilizar membresías vecinales.
- Los titulares deben tener un mecanismo auditado de recuperación y transferencia; no se debe permitir que el último titular se revoque accidentalmente.

## Decisiones que deben cerrarse antes de escribir las RPC

1. **Titular inicial:** alta presencial/verificada por un administrador de red, o código de activación entregado por un responsable autorizado. No se debe permitir que cualquiera que conozca la dirección se convierta en titular.
2. **Múltiples unidades por persona:** el esquema admite que una cuenta tenga membresías en distintas unidades, pero cada una debe aprobarse por separado.
3. **Recuperación:** procedimiento asistido y auditado si se pierde la cuenta del titular.
4. **Menores:** un adulto tutor administra la autorización; el menor no se trata como titular por defecto.

## Criterios de prueba aislada

- Dos integrantes activos de la misma unidad acceden con cuentas distintas.
- Revocar a uno no afecta al otro.
- Un usuario de otra unidad del mismo edificio no ve datos ni recibe alertas privadas.
- Un token expirado, revocado o ya usado no crea otra solicitud.
- Dos canjes concurrentes del mismo token producen como máximo una solicitud.
- Un usuario sin sesión no puede invocar operaciones protegidas.
- Un usuario no puede aprobarse a sí mismo ni aprobar membresías de otra unidad.
- No se filtran hashes, tokens, datos médicos ni domicilios de terceros.
- Todas las operaciones sensibles generan auditoría.

## Límite actual

Este diseño y su SQL son borradores. No crean ni autentican usuarios, no implementan las RPC, no envían notificaciones y no han sido ejecutados. Deben probarse primero en un proyecto Supabase desechable.
