# VIGIARED v0.2 — Módulo vecinal QR + PIN

**Estado:** implementación inicial propuesta, pendiente de revisión técnica y pruebas.  
**Rama:** integracion-segura-2026-11-04.  
**No ejecutar ni desplegar en producción todavía.**

## Archivos

- `supabase/migrations/20261105110000_vigiared_manzanas_domicilios_pin.sql`
- `supabase/functions/vigiared-pin/index.ts`
- `supabase/migrations/20261105150000_vigiared_alta_responsable_consentimiento.sql`

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

Configurar `VIGIARED_PIN_HMAC_SECRET` y `VIGIARED_INVITACION_HMAC_SECRET` como secretos independientes de Edge Function: valores aleatorios de al menos 32 bytes cada uno. El primero protege los PIN y el segundo los tokens de invitación. No guardarlo en el repositorio, SQL, navegador ni logs. `SUPABASE_URL` y `SUPABASE_ANON_KEY` son las variables públicas estándar de Supabase. `SUPABASE_SERVICE_ROLE_KEY` es un secreto privilegiado que sólo puede existir en el entorno servidor de la Edge Function.

## Limitaciones deliberadas de esta primera entrega

- El alta vecinal se bloquea si Supabase Auth no confirma un teléfono o correo electrónico. Guardar un número o correo en el perfil no equivale a verificarlo.
- El primer responsable debe aceptar expresamente una invitación vinculada a su identidad verificada. La designación administrativa por sí sola no activa la membresía.
- El PIN se entrega una sola vez en la respuesta de creación/rotación. La interfaz debe advertir al operador que lo copie o imprima en el momento y no lo guarde en capturas ni chats inseguros.
- El QR todavía no genera una imagen; la respuesta de crear manzana devuelve el identificador público para que la interfaz lo codifique como QR.
- No se conceden permisos directos sobre las tablas nuevas. Las operaciones pasan por RPC con `SECURITY DEFINER`. Las RPC administrativas que persisten HMAC sólo pueden ejecutarse con `service_role` desde la Edge Function; las RPC de consulta/aprobación usan `authenticated` y verifican el actor dentro de la base.
- No se activan SMS, WhatsApp, proveedores pagos ni despliegue automático.

## Flujo implementado en rama de desarrollo: primer responsable

La migración v0.4 separa el registro del domicilio de la asignación del responsable:

1. `crear_domicilio_pendiente` registra la unidad sin membresía responsable y sin PIN.
2. `crear_invitacion_responsable` guarda el HMAC del token, el correo destinatario normalizado y un vencimiento máximo de siete días. La Edge Function genera token aleatorio y lo devuelve una sola vez para entrega manual; no envía correos ni mensajes.
3. La persona destinataria inicia sesión con su propia cuenta y acepta con el token.
4. La Edge Function valida el JWT mediante `auth.getUser`; la RPC comprueba que el correo autenticado esté verificado y coincida exactamente con el destinatario.
5. En una transacción, la RPC consume la invitación, crea la membresía responsable y registra el HMAC de un PIN nuevo. La Edge Function devuelve ese PIN una sola vez.
6. Las invitaciones pendientes pueden revocarse. El token usado, vencido o revocado no se acepta.

La acción anterior `crear_domicilio`, que asignaba directamente un `responsable_user_id`, queda rechazada por la Edge Function con `FLUJO_RESPONSABLE_ACTUALIZADO`. No debe utilizarse.

**Estado de interfaz en rama:** `admin.html` ya incorpora selección de manzana, registro de domicilio pendiente y generación/copia manual del token de invitación; después de copiarlo, el código se borra de la pantalla. `terminal.html` incorpora creación de cuenta, inicio de sesión, ingreso del token y aceptación desde la cuenta individual. Tras aceptar, muestra el PIN una sola vez y permite ocultarlo. La constante `MODULE_READY` permanece en `false`: no se habilitan autenticación, alta ni aceptación hasta desplegar y verificar migraciones, secretos y Edge Function en un entorno de pruebas aprobado. No están desplegados en Supabase real.

## Revisión necesaria antes de ejecutar

1. Validar sintaxis y orden de creación de índices/funciones en una base aislada.
2. Confirmar que el esquema y las firmas de funciones v0.1 coinciden con el proyecto.
3. Revisar política de bloqueo y concurrencia, especialmente intentos simultáneos.
4. Probar invitación/aceptación desde las dos interfaces: identidad destinataria, vencimiento, uso único, revocación y auditoría.
5. Probar aislamiento entre organizaciones, privilegios y cuentas sin correo verificado.
6. Probar rotación: PIN anterior no funciona y membresías existentes permanecen.
7. Revisar la entrega única del token y PIN, su ocultamiento y la ausencia de logs sensibles.
8. Corregir cualquier hallazgo antes de aplicar la migración.

## Nota de seguridad

El digest HMAC se calcula en servidor con secreto fuera de la base. El PIN tiene 10 cifras y se genera con Web Crypto. La protección contra fuerza bruta incluye bloqueo por usuario/manzana; antes de producción conviene añadir limitación adicional por IP o riesgo en una capa que preserve privacidad y evite que una cuenta cree múltiples intentos concurrentes. El endpoint debe usar HTTPS y nunca registrar cuerpos de solicitud.
