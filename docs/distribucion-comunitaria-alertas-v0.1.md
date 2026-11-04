# VIGIARED — Distribución comunitaria de alertas v0.1

## Separación de canales

**COM / operaciones:** conserva el detalle autorizado de la alerta original: domicilio declarado, contacto, ubicación, ficha relevante y estado operativo según el rol.

**Red vecinal:** recibe un aviso mínimo y uniforme. No recibe nombre, teléfono, domicilio exacto, ficha médica, coordenadas ni texto libre del denunciante. El detalle adicional se consulta dentro de la app, autenticado y con permisos.

## Destinatarios

La audiencia se calcula en servidor desde la manzana asociada a la alerta y las membresías activas de unidades que participan en la red. El cliente no puede enviar una lista de destinatarios ni elegir otra manzana.

El modelo admite hogares, departamentos, habitaciones, comercios y unidades mixtas. Cada integrante necesita su propia membresía activa. La revocación bloquea futuras difusiones para esa cuenta/unidad.

## Entrega técnica

- Crear alerta y evento de difusión en una misma transacción.
- Usar una cola durable para las entregas.
- Worker/Edge Function procesa la cola con bloqueo concurrente, reintentos y backoff.
- Web Push para navegadores; FCM/APNs para apps móviles si se implementan.
- Supabase Realtime puede actualizar pantallas abiertas, pero no garantiza notificaciones cuando la app está cerrada.
- Registrar por separado aceptación del proveedor, entrega confirmada y lectura en la aplicación. No prometer que todos los teléfonos reciben cada alerta.

## Datos incorporados en el borrador SQL

- `alertas.manzana_id`: vínculo relacional explícito, nullable; no se rellena inferiendo nombres de manzana de los datos históricos/ficticios.
- `difusiones_comunitarias`: evento mínimo relacionado con una alerta.
- `entregas_notificacion_vecinal`: cola por membresía destinataria, con estado y reintentos.
- `dispositivos_vecinales`: tokens de dispositivos cifrados en backend, nunca expuestos directamente.

## Bloqueantes antes de conectar el SOS

1. Resolver bootstrap de primer titular y alta verificada de integrantes.
2. Crear RPC de alerta que derive manzana/unidad desde la membresía autenticada; retirar el uso de PIN compartido para el flujo nuevo.
3. Definir si el emisor recibe su propia difusión y reglas de prioridad/duplicados.
4. Implementar worker seguro y gestión de secretos push.
5. Definir retención, eliminación y acceso a datos de alertas.
6. Probar aislamiento de manzanas, membresías revocadas, colas duplicadas, reintentos y proveedor push caído en proyecto aislado.

## Criterios de aceptación

- Una alerta de una manzana nunca genera destinatarios de otra.
- Solo miembros activos de unidades participantes reciben aviso.
- La revocación evita nuevas entregas.
- Los payloads push no contienen datos personales ni médicos.
- Un mismo evento no crea dos entregas para la misma membresía.
- Los fallos se reintentan sin duplicar el evento.
- La interfaz no muestra “entregada” cuando solo se aceptó la solicitud del proveedor.
