# VIGIARED — Aprobación, revocación y contexto vecinal v0.1

Estado: borrador SQL; no ejecutado ni probado.

## Operaciones incorporadas al diseño

- `aprobar_ingreso_vecinal`: el titular activo de la unidad aprueba una solicitud solo si la ficha vecinal verificada está vinculada al mismo usuario Auth y a la misma unidad.
- `rechazar_ingreso_vecinal`: el titular puede rechazar una solicitud pendiente con motivo acotado.
- `revocar_membresia_vecinal`: el titular puede revocar integrantes; cada usuario también puede darse de baja. No permite dejar una unidad sin titular activo.
- `mi_contexto_vecinal`: devuelve únicamente membresías activas de la sesión actual, sin aceptar un ID de usuario del cliente.

## Condición fundamental de identidad

Se agrega `vecinos.auth_user_id` como vínculo único nullable. Los registros históricos/ficticios quedan sin vincular. La ficha debe ser creada o asociada por un backend de confianza después de verificar identidad; el nombre y teléfono declarados en una solicitud no son prueba suficiente.

## Riesgos y trabajo pendiente

1. Bootstrap verificado del primer titular: no existe todavía y no debe resolverse con autoasignación.
2. Transferencia de titularidad: necesaria antes de que el último titular pueda salir.
3. Revisión de concurrencia al revocar titulares y aprobación simultánea.
4. Notificación segura al solicitante después de aprobar/rechazar.
5. Revisión del acceso a datos de solicitudes y auditoría.
6. La revocación bloquea la fila de unidad para serializar operaciones concurrentes y proteger la regla del último titular; probar carreras con dos sesiones en un proyecto Supabase aislado.
7. Pruebas en un proyecto Supabase aislado, incluyendo doble aprobación, doble revocación y último titular.

## Pruebas de aceptación

- Titular A no puede aprobar solicitudes de unidad B.
- Una solicitud no se puede aprobar con una ficha vecinal vinculada a otra cuenta o unidad.
- Una solicitud ya resuelta no se puede resolver de nuevo.
- Un usuario no titular no puede aprobar ni rechazar.
- Un integrante puede darse de baja sin afectar a otros integrantes.
- Un titular puede revocar a otro integrante, pero no dejar la unidad sin titular.
- `mi_contexto_vecinal()` no acepta ni filtra por identidad arbitraria.
- Las acciones sensibles quedan auditadas.
