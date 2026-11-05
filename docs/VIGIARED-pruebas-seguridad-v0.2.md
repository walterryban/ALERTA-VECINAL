# VIGIARED v0.2 — plan de pruebas previo a Supabase

**Estado:** casos definidos; NO ejecutados. No aplicar la migración a producción.

## Entorno requerido

- Proyecto Supabase de prueba aislado o rama de base de datos restaurable.
- Nunca usar domicilios, teléfonos ni datos reales.
- Cuenta A: propietario global.
- Cuenta B: administrador activo de una organización de prueba.
- Cuenta C: usuario sin rol organizacional.
- Cuenta D: usuario con teléfono Auth confirmado (sólo si el proveedor de verificación está habilitado de forma autorizada).
- Cuenta E: usuario sin teléfono confirmado.
- QR y PIN generados exclusivamente en entorno de prueba.

## Casos funcionales

| ID | Caso | Resultado esperado |
|---|---|---|
| F-01 | Propietario crea manzana en su organización | Creación correcta y evento de auditoría |
| F-02 | Administrador activo crea manzana de su organización | Creación correcta |
| F-03 | Operador, supervisor o auditor intenta crear manzana | Denegado |
| F-04 | Usuario sin rol intenta crear manzana | Denegado |
| F-05 | Administrador crea domicilio en manzana de otra organización | Denegado |
| F-06 | Alta de domicilio con responsable existente y teléfono Auth confirmado | Domicilio, membresía responsable y HMAC creados en una transacción |
| F-07 | Alta con usuario inexistente o sin teléfono confirmado | Rechazada sin crear registros parciales |
| F-08 | Solicitud con PIN correcto y teléfono confirmado | Solicitud pendiente; no se crea membresía todavía |
| F-09 | Solicitud con PIN incorrecto | Respuesta genérica; contador incrementado |
| F-10 | Quinto intento incorrecto dentro de ventana | Bloqueo temporal de 15 minutos |
| F-11 | Cuenta bloqueada intenta PIN correcto | Rechazada durante el bloqueo |
| F-12 | Solicitud con teléfono no confirmado invocando Edge Function | Denegada |
| F-13 | Solicitud con teléfono no confirmado invocando RPC directamente | Denegada también |
| F-14 | Responsable aprueba solicitud de su domicilio | Membresía individual activa y auditoría |
| F-15 | Responsable de otro domicilio intenta aprobar | Denegado |
| F-16 | Administrador de otra organización intenta aprobar | Denegado |
| F-17 | Responsable rota PIN | PIN anterior deja de validar; nuevo PIN funciona |
| F-18 | Rotación de PIN | Membresías actuales permanecen intactas |
| F-19 | QR se comparte sin PIN | No otorga acceso a información privada |
| F-20 | Repetición de solicitud pendiente | No duplica la solicitud |

## Casos de seguridad

- Confirmar RLS ENABLED y FORCE en las tres tablas nuevas.
- Confirmar que anon y authenticated no tienen SELECT/INSERT/UPDATE/DELETE directos sobre las tablas nuevas.
- Confirmar que `crear_domicilio_con_responsable` y `rotar_pin_domicilio` NO tienen EXECUTE para `authenticated` y sí para `service_role`.
- Confirmar que `crear_manzana`, `solicitar_ingreso_con_pin`, `resolver_solicitud_ingreso` y `listar_solicitudes_ingreso_pendientes` tienen sólo los permisos previstos para `authenticated`.
- Confirmar que la función helper interna no es invocable directamente.
- Probar aislamiento entre dos organizaciones.
- Comprobar que ningún PIN ni HMAC aparece en logs, auditoría, URL o QR.
- Confirmar que el secreto HMAC no está en Git, SQL, frontend ni respuestas.
- Probar llamadas simultáneas para evitar saltos del límite de intentos.
- Verificar que errores no revelen si un PIN corresponde a un domicilio concreto.

## Hallazgos que deben resolverse antes de producción

1. Añadir limitación de abuso adicional por IP/riesgo sin almacenar más datos personales de los necesarios.
2. Revisar la autorización de alta y rotación de credenciales para que la generación y persistencia del HMAC sólo puedan ocurrir mediante el backend confiable.
3. Revisar CORS: reemplazar el comodín por los orígenes oficiales de la aplicación cuando se integre.
4. Definir el procedimiento de consentimiento y entrega del PIN al primer responsable.
5. Resolver una verificación telefónica real y sostenible sin costo antes de habilitar el ingreso vecinal.
6. Incorporar consultas seguras para que responsables vean solicitudes pendientes y puedan resolverlas.
7. Revisar accesibilidad WCAG 2.2 AA del flujo QR/PIN y probarlo con usuarios.

## Casos añadidos tras revisión de seguridad

| ID | Caso | Resultado esperado |
|---|---|---|
| S-01 | Usuario `authenticated` invoca directamente RPC de alta de domicilio | Denegado por permisos EXECUTE |
| S-02 | Usuario `authenticated` invoca directamente RPC de rotación de PIN | Denegado por permisos EXECUTE |
| S-03 | Edge Function llama RPC privilegiada con actor administrador válido | Operación permitida y auditada |
| S-04 | Edge Function intenta alta con actor sin rol autorizado | RPC rechaza; no crea registros |
| S-05 | Responsable consulta solicitudes de su domicilio | Devuelve sólo solicitudes pendientes y datos mínimos |
| S-06 | Vecino o responsable de otro domicilio consulta solicitudes | Denegado |
| S-07 | Membresía revocada vuelve a solicitar ingreso y responsable aprueba | Se reactiva como `miembro` |
| S-08 | Membresía suspendida vuelve a solicitar ingreso y responsable aprueba | Se reactiva como `miembro` |
| S-09 | Membresía ya activa intenta volver a ingresar | No duplica ni modifica la membresía |


## Revisión adicional de Edge Function (05-11-2026)

La Edge Function `vigiared-pin` se endureció antes de cualquier despliegue:

- CORS ya no usa `*`: exige coincidencia exacta con `VIGIARED_ALLOWED_ORIGINS` para solicitudes de navegador.
- Respuestas con `Cache-Control: no-store` y `Pragma: no-cache`, especialmente importante para la entrega única del PIN.
- Verificación de método, tipo de contenido, tamaño máximo del cuerpo, JSON y formato de identificadores.
- Validación de sesión mediante `auth.getUser(accessToken)`.
- La clave `service_role` sólo se utiliza dentro de la Edge Function para RPC privilegiadas; el actor se deriva del usuario autenticado y la base vuelve a validar su rol.
- El PIN sólo se devuelve una vez al crear o rotar; el HMAC y los secretos no se devuelven ni se escriben en auditoría.

### Variables requeridas antes de desplegar

Configurar en el entorno de Edge Functions, nunca en el frontend ni en Git:
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `VIGIARED_PIN_HMAC_SECRET` (mínimo 32 bytes aleatorios)
- `VIGIARED_ALLOWED_ORIGINS` (orígenes exactos separados por coma; sin comodines)

No se deben inventar ni fijar dominios hasta decidir cuáles serán los orígenes oficiales. Mientras la lista esté vacía, las solicitudes de navegador se rechazan por diseño. Las llamadas server-to-server sin cabecera Origin siguen siendo posibles.

### Casos pendientes de prueba antes de despliegue

- CORS: origen autorizado aceptado; origen no listado y lista vacía rechazados.
- PIN de alta/rotación: respuesta no cacheable y entrega única; nunca en logs, QR, URL ni auditoría.
- Solicitudes malformadas, JSON inválido, contenido no JSON y cuerpo mayor al límite rechazados.
- Acciones privilegiadas desde usuario sin rol organizacional rechazadas por la RPC.
- Verificación telefónica real sigue pendiente; no habilitar el acceso vecinal productivo hasta contar con un método autorizado y sostenible sin costo.
- El límite de intentos actual es por usuario y manzana. Antes de producción hay que reforzarlo contra abuso distribuido entre múltiples cuentas, sin introducir costes ni recopilar datos innecesarios.

La CI ahora ejecuta `deno check` sobre la Edge Function además de las pruebas PostgreSQL aisladas. No implica despliegue ni uso de secretos reales.

## Criterio de aprobación

No ejecutar en producción hasta que todos los casos funcionales y de seguridad aplicables pasen en un entorno aislado, el SQL haya sido validado por el motor PostgreSQL y se haya revisado la integración de Edge Function. No activar SMS/WhatsApp pagos ni iniciar pruebas con usuarios reales sin autorización.
