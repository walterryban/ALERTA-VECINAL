# VIGIARED — Diseño de alertas comunitarias v0.1

**Estado:** diseño técnico para revisión; no es una migración ejecutable.  
**Rama:** integracion-segura-2026-11-04.  
**Presupuesto:** cero pesos. No habilitar proveedores externos, SMS, WhatsApp ni notificaciones pagas.  
**Producción:** no ejecutar SQL ni desplegar funciones hasta completar revisión y pruebas aisladas.

## 1. Objetivo

Una persona con membresía activa genera una alerta desde su cuenta y domicilio. El evento debe llegar:

1. Al Centro de Monitoreo de la organización correspondiente.
2. A los integrantes con membresía activa de los domicilios de la misma manzana, según las reglas de distribución.
3. Al propio emisor, para mostrar confirmación y estado.

La autorización se calcula en el servidor. El navegador no decide quién recibe una alerta.

## 2. Destinatarios y alcance

- Emisor: usuario autenticado con membresía activa en la unidad desde la que reporta.
- Vecinos: sólo usuarios con membresía activa en unidades activas de la misma manzana y organización.
- Centro de Monitoreo: propietario global con vista de supervisión; administrador y supervisor activos de la organización; operador activo con permiso operativo.
- Auditor: lectura de los registros autorizados, sin capacidad de crear alertas ni cambiar su estado.
- No enviar a otras organizaciones ni a otras manzanas.
- No incluir teléfono, correo ni ficha médica del emisor en la notificación vecinal.
- El detalle visible a vecinos debe ser mínimo: tipo, hora, manzana, domicilio o referencia de ubicación autorizada y estado. Los datos identificatorios adicionales sólo estarán disponibles a roles autorizados y con justificación.

## 3. Modelo de datos propuesto

### `alertas`
- `id` UUID.
- `organizacion_id`, `manzana_id`, `unidad_id`.
- `creada_por` UUID del usuario autenticado.
- `tipo`: allowlist inicial `emergencia`, `asistencia`, `robo`, `coaccion`, `incendio`, `otra`.
- `descripcion` opcional, longitud limitada.
- `estado`: `pendiente`, `en_proceso`, `resuelta`, `cancelada`.
- `direccion_snapshot` y `manzana_snapshot` para conservar la referencia al momento del evento aunque luego se edite el domicilio.
- `latitud`, `longitud` opcionales, sólo si el usuario autoriza compartir ubicación y el dispositivo la entrega.
- `created_at`, `updated_at`, `resuelta_at`.

### `alertas_destinatarios`
- `alerta_id`, `user_id`.
- `unidad_id` de la membresía destinataria.
- `estado_entrega` interno: `pendiente`, `notificada_en_sesion`, `vista`.
- `created_at`, `vista_at`.
- Restricción única por `alerta_id,user_id` para evitar duplicados si una persona tiene más de una membresía en la misma manzana.

La tabla de destinatarios sirve para fijar quién estaba autorizado al momento de crear la alerta. La baja posterior de una membresía no debe ampliar el acceso; el detalle de cada alerta seguirá verificando autorización actual y reglas de privacidad.

## 4. Flujo transaccional

1. El cliente envía tipo, descripción opcional y consentimiento/ubicación opcional a una Edge Function con JWT.
2. La Edge Function valida sesión y formato. No acepta `creada_por`, `organizacion_id`, `manzana_id` ni destinatarios decididos por el cliente.
3. Una RPC segura deriva el usuario desde la sesión, verifica membresía activa y obtiene organización, manzana, domicilio y dirección desde la base.
4. En una sola transacción crea la alerta, crea los destinatarios de esa manzana y registra auditoría.
5. La respuesta confirma el identificador y la recepción por el servidor; no afirma que un teléfono apagado o desconectado haya recibido una notificación.
6. El Centro de Monitoreo y los clientes vecinales autorizados actualizan su vista mediante un mecanismo Realtime protegido por RLS o canal privado. Debe probarse aislamiento entre usuarios, domicilios, manzanas y organizaciones antes de elegir la implementación final.
7. Un operador autorizado cambia el estado mediante RPC; se registra actor, estado anterior/nuevo y hora en auditoría.

## 5. Entrega y límites de la primera versión

- Realtime significa actualización mientras la aplicación está abierta y conectada.
- No equivale a notificación push en segundo plano ni garantiza que el usuario vea la alerta.
- Push web/móvil, SMS y WhatsApp quedan fuera de esta versión hasta validar compatibilidad, privacidad, costes y autorización expresa.
- No presentar VIGIARED como servicio de despacho de emergencias ni como reemplazo de 911/107/100.
- La pantalla debe indicar claramente si el servidor recibió el evento y qué canal está activo.

## 6. Seguridad y privacidad obligatorias

- Sin INSERT/UPDATE directo de alertas desde el navegador; operaciones mediante RPC/Edge Function.
- RLS ENABLED y FORCE; permisos mínimos y políticas explícitas para lectura en tiempo real.
- No confiar en IDs de organización, manzana, unidad o usuario enviados por el cliente.
- Comprobar membresía activa al crear la alerta y al consultar su detalle.
- No exponer la alerta a toda la organización por defecto: el alcance vecinal es la manzana.
- Idempotencia para evitar alertas duplicadas por doble toque o reintento de red.
- Rate limiting por cuenta y controles adicionales de abuso; sin recopilar datos personales innecesarios.
- Auditoría de creación, acceso relevante y cambios de estado, sin tokens ni datos sensibles.
- Ubicación GPS opcional, con consentimiento explícito; si no hay permiso, usar la dirección registrada del domicilio.
- Botones accesibles, grandes y con texto; confirmación visual, sonora y vibratoria cuando el dispositivo lo permita.

## 7. Casos mínimos de prueba

| ID | Prueba | Resultado esperado |
|---|---|---|
| A-01 | Vecino con membresía activa crea alerta | Se crea una alerta asociada al domicilio real de su membresía |
| A-02 | Usuario sin membresía activa intenta crear | Denegado |
| A-03 | Cliente intenta suplantar unidad/organización/usuario | Los valores se ignoran; el servidor deriva el contexto |
| A-04 | Dos vecinos activos en la misma manzana | Ambos reciben evento autorizado |
| A-05 | Vecino de otra manzana intenta consultar | Denegado |
| A-06 | Usuario de otra organización intenta consultar | Denegado |
| A-07 | Operador de la organización consulta | Permitido según permiso operativo |
| A-08 | Auditor intenta cambiar estado | Denegado |
| A-09 | Operador autorizado cambia estado | Cambio auditado |
| A-10 | Doble envío con la misma clave de idempotencia | Una sola alerta |
| A-11 | Usuario sin permiso GPS | La alerta puede crearse con domicilio registrado |
| A-12 | Aplicación cerrada o teléfono desconectado | No afirmar recepción push; mostrar sólo confirmación del servidor |
| A-13 | Usuario revocado intenta abrir alerta anterior | Se aplica política de acceso actual; no se amplían permisos |
| A-14 | Dos organizaciones comparten nombres de manzana | No hay cruce de destinatarios |

## 8. Decisiones que deben validarse antes de SQL

1. Confirmar la regla de distribución inicial: todos los miembros activos de la misma manzana reciben la alerta, sin excepción por tipo.
2. Definir qué datos exactos ven los vecinos y qué datos quedan sólo para operadores autorizados.
3. Definir si el estado `resuelta` lo puede cambiar sólo un operador o también el emisor.
4. Probar la estrategia Realtime con RLS en una base aislada.
5. Resolver la autenticación telefónica real sin coste antes de habilitar el alta vecinal productiva.

**No ejecutar este documento como SQL.** Primero se aprueba el alcance, luego se construye una migración separada, pruebas automatizadas y revisión de seguridad.
