# Revisión técnica rápida — identidad vecinal v0.1

## Nuevo avance

Se agregó un borrador SQL de dos operaciones:
- `emitir_invitacion_vecinal`: solo un titular ya activo puede emitir una invitación de un solo uso.
- `solicitar_ingreso_vecinal`: requiere sesión Auth, valida el token con hash SHA-256, bloquea la invitación durante el canje y crea una solicitud pendiente.

El token original no queda almacenado en la base; se devuelve una sola vez al emisor. El canje no activa automáticamente el acceso.

## Bloqueos detectados que no se deben ocultar

1. **Todavía no existe el bootstrap del primer titular.** Sin un procedimiento controlado de verificación, no se debe permitir que cualquier usuario se autoproclame titular.
2. **La tabla heredada `public.vecinos` necesita una integración verificada.** No se debe crear una membresía definitiva a partir de nombre y teléfono declarados en el navegador.
3. **Falta la RPC de aprobación/rechazo**, incluyendo la creación o vinculación canónica del integrante y la validación de autoridad del titular.
4. **Falta verificación de teléfono/identidad y defensa contra enumeración**, además de ensayos de concurrencia y consumo de invitaciones.
5. **El borrador no está probado** y depende de que las dos migraciones de esquema anteriores hayan sido ensayadas primero.

## Decisión de seguridad

No conectar todavía estas RPC a la terminal ni desplegarlas. El flujo queda deliberadamente en solicitud pendiente hasta que la identidad pueda verificarse y aprobarse correctamente. Es preferible detener un alta que admitir a una persona en el domicilio equivocado.

## Pruebas requeridas en entorno aislado

- Usuario anónimo no puede emitir ni canjear.
- Usuario autenticado sin membresía titular no puede emitir.
- Titular solo emite para su propia unidad activa.
- Token inválido, expirado, revocado o usado se rechaza.
- Dos canjes concurrentes del mismo token producen como máximo una solicitud.
- El usuario no puede autoaprobarse.
- Los datos declarados no conceden identidad ni permisos por sí mismos.
- El historial de auditoría no contiene tokens ni datos sensibles innecesarios.
