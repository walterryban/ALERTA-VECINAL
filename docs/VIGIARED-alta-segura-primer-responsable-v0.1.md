# VIGIARED — Alta segura del primer responsable v0.1

**Estado:** diseño funcional y de seguridad; pendiente de implementación y pruebas.  
**Presupuesto:** cero pesos. No enviar correos, SMS ni WhatsApp automáticamente ni activar servicios pagos.  
**Producción:** no ejecutar ni desplegar hasta revisión y aprobación.

## 1. Objetivo

Permitir que una organización registre un domicilio sin convertir a una persona en responsable sin su conocimiento. La responsabilidad se activa únicamente después de que la persona destinataria se autentica con su propia cuenta y acepta expresamente la invitación.

## 2. Regla fundamental

- Crear un domicilio y asignar un responsable son dos operaciones distintas.
- El administrador puede iniciar una invitación, pero no puede aceptar en nombre del vecino.
- Conocer un UUID, teléfono o correo no demuestra consentimiento.
- La membresía `responsable` sólo pasa a activa después de la aceptación autenticada.
- Si la invitación vence, se revoca o no se acepta, el domicilio queda registrado pero sin responsable activo.
- El PIN de domicilio se entrega al responsable después de aceptar, mediante una respuesta de una sola visualización o entrega controlada. No se incluye en el QR.

## 3. Flujo propuesto sin costos de mensajería

1. Un administrador autorizado crea el domicilio con estado operativo pendiente de responsable. No se crea una membresía responsable activa.
2. El administrador ingresa el correo electrónico que la persona declara como propio y que deberá tener verificado en su cuenta VIGIARED/Supabase Auth.
3. El servidor genera un token de invitación aleatorio, de un solo uso y con vencimiento. En la base se guarda sólo su hash; nunca el token legible.
4. La interfaz administrativa muestra una única vez un enlace de aceptación para copiar o entregar personalmente. No se envía automáticamente por email, SMS o WhatsApp en esta etapa.
5. La persona abre el enlace, inicia sesión con su cuenta individual y confirma que acepta ser responsable de ese domicilio.
6. El backend valida el token, su vigencia y estado, el correo confirmado de la cuenta autenticada y la coincidencia exacta con el destinatario normalizado de la invitación.
7. En una transacción, el backend consume la invitación, crea o activa la membresía `responsable`, registra auditoría y habilita la entrega inicial del PIN.
8. La persona recibe el PIN una sola vez y puede compartirlo con los integrantes de su vivienda según las reglas comunitarias.
9. Los integrantes adicionales se incorporan con QR de manzana + PIN de domicilio y quedan como solicitudes pendientes hasta aprobación.

## 4. Seguridad y privacidad

- No mostrar directorios de usuarios, UUID de Auth, teléfonos ni correos de otras personas.
- No confirmar públicamente si un correo está registrado. La respuesta administrativa debe ser genérica.
- Normalizar el correo de forma consistente y comparar sólo contra el correo confirmado de la sesión autenticada.
- Token generado con aleatoriedad criptográfica; almacenar HMAC/hash resistente y secreto sólo en servidor, nunca en navegador.
- Token de un solo uso, vencimiento corto configurable, revocación y protección contra reintentos concurrentes.
- Aceptación transaccional e idempotente: dos clics o dos solicitudes simultáneas no pueden crear dos responsables.
- Registrar actor, domicilio, destinatario en forma minimizada, fecha, resultado y evento de auditoría. Nunca registrar token ni PIN.
- El administrador puede revocar una invitación pendiente y emitir otra. No puede convertirla en aceptada.
- El responsable puede renunciar; la organización debe poder iniciar una nueva invitación sin dejar permisos residuales.
- El acceso del responsable se limita a su domicilio; no concede administración de la organización.
- El PIN no se envía por email automáticamente ni se guarda en logs, URL o QR.

## 5. Alternativa telefónica

El correo electrónico verificado es el método de aceptación inicial sin costo de mensajería. Un teléfono sólo puede usarse como alternativa cuando Supabase Auth lo marque realmente como verificado y exista un canal de entrega/aceptación seguro, aprobado y sostenible. No asumir que SMS o WhatsApp son gratuitos.

## 6. Ajustes necesarios respecto de la implementación propuesta actual

La RPC `crear_domicilio_con_responsable` y la acción Edge Function `crear_domicilio` actuales reciben `responsable_user_id` y activan directamente una membresía `responsable`. Ese comportamiento no satisface la regla de consentimiento explícito.

Por lo tanto:
- No habilitar todavía esa acción desde el panel ni usarla para altas reales.
- Separar la creación del domicilio de la aceptación de responsabilidad.
- Implementar RPC/Edge Function específicas para crear invitación, consultar estado mínimo y aceptar/revocar invitación.
- Reutilizar `invitaciones` sólo después de revisar sus constraints, estados y firmas existentes; no asumir que sus valores actuales admiten este flujo.
- Mantener la generación y entrega del PIN exclusivamente en servidor.
- No ejecutar migraciones en Supabase real ni desplegar la Edge Function hasta completar pruebas aisladas.

## 7. Pruebas obligatorias

- Invitación válida y correo verificado coincidente: aceptación exitosa.
- Correo diferente, no verificado o ausente: rechazo sin revelar datos de la cuenta destinataria.
- Token inválido, vencido, revocado o ya usado: rechazo.
- Dos aceptaciones concurrentes: una sola membresía responsable.
- Administrador intenta aceptar por el vecino: rechazo.
- Vecino no autenticado: rechazo.
- Invitación revocada antes de aceptar: rechazo.
- Organización o domicilio suspendido/inactivo: rechazo.
- Aceptación repetida: resultado idempotente sin duplicar membresías ni auditoría indebida.
- El PIN se muestra sólo tras la aceptación y no aparece en logs, URL, QR ni almacenamiento cliente persistente.
- Aislamiento entre organizaciones y permisos limitados al domicilio.
- El flujo completo funciona sin enviar emails, SMS ni WhatsApp pagos.

## 8. Criterio de salida

El módulo se considera listo para revisión cuando crear domicilio, invitar, aceptar, asignar responsable, entregar PIN y auditar estén implementados y probados en PostgreSQL aislado, con CI exitoso. Hasta entonces, la creación directa con `responsable_user_id` queda como implementación no habilitada.
