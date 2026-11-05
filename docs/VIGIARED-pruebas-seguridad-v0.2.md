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
- Confirmar que sólo las RPC previstas tienen EXECUTE para authenticated.
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

## Criterio de aprobación

No ejecutar en producción hasta que todos los casos funcionales y de seguridad aplicables pasen en un entorno aislado, el SQL haya sido validado por el motor PostgreSQL y se haya revisado la integración de Edge Function. No activar SMS/WhatsApp pagos ni iniciar pruebas con usuarios reales sin autorización.
