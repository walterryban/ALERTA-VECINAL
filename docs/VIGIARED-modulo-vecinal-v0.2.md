# VIGIARED v0.2 — Módulo vecinal QR + PIN

**Estado:** implementación inicial propuesta, pendiente de revisión técnica y pruebas.  
**Rama:** integracion-segura-2026-11-04.  
**No ejecutar ni desplegar en producción todavía.**

## Archivos

- `supabase/migrations/20261105110000_vigiared_manzanas_domicilios_pin.sql`
- `supabase/functions/vigiared-pin/index.ts`

## Modelo

- `manzanas`: una organización contiene manzanas. `public_id` es un identificador aleatorio público que puede codificarse en el QR; no contiene PIN ni datos personales.
- `unidades`: se amplía con `manzana_id`; se reutiliza la tabla existente para domicilios.
- `credenciales_domicilio`: guarda exclusivamente HMAC-SHA-256 del PIN y su estado. No se guarda el PIN legible.
- `intentos_pin`: limita intentos por cuenta y manzana.
- `solicitudes_ingreso` y `membresias_unidad`: se reutilizan para el flujo de aprobación.

## Flujo inicial

1. Un propietario global o administrador activo de la organización crea la manzana.
2. El administrador registra el domicilio y designa una cuenta existente como primer responsable.
3. La Edge Function genera un PIN decimal aleatorio de 10 cifras con Web Crypto, calcula HMAC y envía el digest a una RPC transaccional.
4. El PIN legible se devuelve una sola vez en la respuesta para que el administrador lo entregue al responsable por un canal controlado.
5. El QR contiene solamente el `public_id` de la manzana.
6. Un vecino autenticado con teléfono o correo electrónico verificado envía el PIN; la Edge Function calcula HMAC y la RPC crea una solicitud pendiente.
7. El responsable activo o el administrador de la organización consulta las solicitudes pendientes mediante una RPC limitada al domicilio autorizado y aprueba o rechaza la solicitud.
8. La aprobación crea una membresía individual con rol `miembro`.

## Secretos y configuración

Configurar `VIGIARED_PIN_HMAC_SECRET` como secreto de Edge Function: valor aleatorio de al menos 32 bytes. No guardarlo en el repositorio, SQL, navegador ni logs. `SUPABASE_URL` y `SUPABASE_ANON_KEY` son las variables públicas estándar de Supabase. `SUPABASE_SERVICE_ROLE_KEY` es un secreto privilegiado que sólo puede existir en el entorno servidor de la Edge Function.

## Limitaciones deliberadas de esta primera entrega

- El alta vecinal se bloquea si Supabase Auth no confirma un teléfono o correo electrónico. Guardar un número o correo en el perfil no equivale a verificarlo.
- El primer responsable debe aceptar expresamente una invitación vinculada a su identidad verificada. La designación administrativa por sí sola no activa la membresía.
- El PIN se entrega una sola vez en la respuesta de creación/rotación. La interfaz debe advertir al operador que lo copie o imprima en el momento y no lo guarde en capturas ni chats inseguros.
- El QR todavía no genera una imagen; la respuesta de crear manzana devuelve el identificador público para que la interfaz lo codifique como QR.
- No se conceden permisos directos sobre las tablas nuevas. Las operaciones pasan por RPC con `SECURITY DEFINER`. Las RPC administrativas que persisten HMAC sólo pueden ejecutarse con `service_role` desde la Edge Function; las RPC de consulta/aprobación usan `authenticated` y verifican el actor dentro de la base.
- No se activan SMS, WhatsApp, proveedores pagos ni despliegue automático.

## Revisión necesaria antes de ejecutar

1. Validar sintaxis y orden de creación de índices/funciones en una base aislada.
2. Confirmar que el esquema y las firmas de funciones v0.1 coinciden con el proyecto.
3. Revisar política de bloqueo y concurrencia, especialmente intentos simultáneos.
4. Implementar y probar invitación/aceptación del primer responsable: identidad destinataria, vencimiento, uso único, revocación y auditoría.
4. Probar aislamiento entre organizaciones, privilegios y cuentas sin teléfono confirmado.
5. Probar rotación: PIN anterior no funciona y membresías existentes permanecen.
6. Revisar la entrega única del PIN en la interfaz y la ausencia de logs sensibles.
7. Corregir cualquier hallazgo antes de aplicar la migración.

## Nota de seguridad

El digest HMAC se calcula en servidor con secreto fuera de la base. El PIN tiene 10 cifras y se genera con Web Crypto. La protección contra fuerza bruta incluye bloqueo por usuario/manzana; antes de producción conviene añadir limitación adicional por IP o riesgo en una capa que preserve privacidad y evite que una cuenta cree múltiples intentos concurrentes. El endpoint debe usar HTTPS y nunca registrar cuerpos de solicitud.
