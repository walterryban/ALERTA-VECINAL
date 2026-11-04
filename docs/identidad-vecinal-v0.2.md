# VIGIARED — Identidad vecinal v0.2

**Estado:** borrador técnico para revisión. No ejecutar ni desplegar.

## Decisión de modelo

Se separan cuenta, identidad y autorización:

- `auth.users`: cuenta de acceso individual.
- `perfiles_vecinales`: perfil único por cuenta.
- `membresias_vecinales`: autorización del perfil en una unidad concreta.

Una persona puede tener un único perfil y varias membresías. Una familia puede incorporar tantos integrantes como necesite, cada uno con su propia cuenta y permiso revocable. Un edificio, hostel, pensión, vivienda con departamentos o inmueble mixto se representa con establecimientos y unidades diferenciadas.

## Flujo previsto

1. Una cuenta se registra y verifica mediante Supabase Auth.
2. Un backend de confianza provisiona el perfil; el navegador no puede insertar perfiles.
3. El primer titular se inicializa únicamente mediante backend con rol `service_role`, tras verificación externa y referencia auditable.
4. El titular emite una invitación de un solo uso para una unidad concreta.
5. La invitación se almacena como hash; el token se entrega una sola vez.
6. El usuario autenticado canjea el token y genera una solicitud pendiente.
7. Un titular activo de esa misma unidad aprueba o rechaza.
8. La membresía resultante se puede revocar sin bloquear la cuenta ni otras membresías.

El QR solo debe abrir VIGIARED o una pantalla de invitación. Nunca debe contener PIN compartidos ni secretos permanentes.

## Controles incluidos en el borrador SQL

- Un perfil por cuenta Auth.
- Unicidad de membresía por perfil y unidad.
- Token aleatorio de 256 bits almacenado como SHA-256.
- Invitaciones de un solo uso, con vencimiento y bloqueo transaccional al canjear.
- Aprobación limitada al titular de la misma unidad.
- Revocación individual y protección contra revocar al último titular.
- Contexto vecinal derivado de `auth.uid()`; el cliente no puede consultar el contexto de otra cuenta.
- RLS activado y privilegios directos revocados en tablas sensibles.
- Provisionamiento y bootstrap reservados a `service_role`.
- Auditoría sin almacenar tokens, PIN ni fichas médicas.

## Compatibilidad y transición

- `public.vecinos` permanece como legado/histórico y no es fuente de autorización.
- No se vinculan registros antiguos por coincidencia de nombre, teléfono, dirección o manzana.
- Las manzanas y alertas existentes son datos ficticios de prueba y no se modifican.
- Los borradores v0.1 de identidad, invitaciones y aprobación quedan **supersedidos** por este diseño y no deben ejecutarse.

## Bloqueos antes de integrar la interfaz

1. Revisar el esquema real y confirmar que no se ejecutó ningún borrador v0.1.
2. Crear un proyecto Supabase aislado para ensayos.
3. Revisar el SQL con pruebas automatizadas y revisión de seguridad.
4. Definir verificación de identidad, teléfono, menores y recuperación/transferencia de titularidad.
5. Implementar consulta segura de solicitudes pendientes para titulares.
6. Probar invitaciones y concurrencia con cuentas y datos sintéticos.
7. Solo después integrar Supabase Auth y las RPC en `terminal.html`.

## Matriz mínima de aceptación

| Caso | Resultado esperado |
|---|---|
| Misma cuenta en dos unidades | Un perfil, dos membresías |
| Revocar unidad A | Unidad B permanece activa |
| Usuario sin perfil | No puede solicitar ingreso |
| Token usado o vencido | Canje rechazado |
| Usuario no titular aprueba | Acceso denegado |
| Titular de unidad A opera unidad B | Acceso denegado |
| Revocar último titular | Operación rechazada |
| Usuario consulta contexto | Solo sus membresías activas |
| Registro histórico en `vecinos` | No obtiene permisos por sí mismo |

**Importante:** el SQL no fue ejecutado ni probado contra PostgreSQL. La migración tiene preflight para detenerse si detecta tablas de identidad existentes o faltan las tablas base. Aun así, necesita revisión y ensayo en un proyecto aislado antes de cualquier aplicación.

## Estado de revisión adicional

Se reforzó el borrador para impedir el canje de invitaciones en unidades/establecimientos suspendidos y para exigir perfil activo al rechazar solicitudes. La matriz completa está en `docs/pruebas-identidad-vecinal-v0.2.md`. Los cambios siguen sin ejecución ni validación en PostgreSQL.
