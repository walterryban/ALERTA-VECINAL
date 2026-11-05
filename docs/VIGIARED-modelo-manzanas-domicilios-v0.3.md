# VIGIARED — Modelo territorial de manzanas y domicilios v0.3

**Estado:** decisión de arquitectura y revisión de compatibilidad. No es SQL ejecutable.  
**Rama:** integracion-segura-2026-11-04.  
**Entorno:** no ejecutar cambios en Supabase compartido; no desplegar ni tocar producción.

## 1. Objetivo

Vincular cada domicilio/unidad a una manzana identificable y a una organización, para que el QR público identifique la manzana y el backend pueda distribuir alertas exclusivamente a sus integrantes activos.

La relación debe ser por claves foráneas UUID, nunca por nombre de manzana, dirección o texto ingresado desde el navegador.

## 2. Hallazgo crítico: colisión con la tabla heredada `public.manzanas`

El proyecto original ya contiene una tabla heredada `public.manzanas` utilizada por la aplicación anterior. La documentación de la arquitectura original registra que su identificador es `bigint` y que el modelo previo vincula alertas por el campo textual `alertas.manzana`.

La migración propuesta `supabase/migrations/20261105110000_vigiared_manzanas_domicilios_pin.sql` intenta ejecutar:

```sql
create table if not exists public.manzanas (...)
```

Esto NO adapta la tabla heredada si ya existe. PostgreSQL conserva la tabla existente, con columnas y tipos anteriores; las funciones posteriores que esperan `organizacion_id`, `public_id`, `estado` UUID y la clave única compuesta podrían fallar o referenciar un modelo incompatible.

**Decisión de seguridad:** no reutilizar ni transformar automáticamente `public.manzanas` en esta etapa. Tampoco asociar alertas o domicilios ficticios históricos por nombre.

## 3. Nombre canónico nuevo

Para aislar la arquitectura VIGIARED de la tabla heredada, el nombre propuesto para la nueva entidad es:

- `public.manzanas_vigiared`
- PK: `id uuid`
- Organización: `organizacion_id uuid NOT NULL REFERENCES public.organizaciones(id)`
- Identificador público del QR: `public_id uuid NOT NULL UNIQUE`, aleatorio y sin datos personales
- Nombre visible: `nombre`
- Estado: `activa | suspendida | inactiva`
- Auditoría de creación/actualización con actor y timestamps

La unicidad compuesta `UNIQUE (organizacion_id, id)` permite que una unidad sólo pueda vincularse a una manzana de su misma organización mediante una FK compuesta.

No se debe usar el nombre visible como clave de seguridad. Dos organizaciones pueden tener una manzana llamada “Manzana 1”.

## 4. Relación con el esquema VIGIARED v0.1

El esquema base verificado ya tiene:

- `organizaciones`
- `unidades`
- `membresias_unidad`
- `perfiles`
- `solicitudes_ingreso`
- `membresias_organizacion`
- `auditoria`
- `propietarios_plataforma`

La tabla `unidades` ya representa el domicilio/unidad funcional y contiene `organizacion_id`, nombre/tipo, dirección y estado. No es necesario crear otra tabla de domicilios ni introducir ahora la jerarquía heredada `establecimientos → unidades`, porque eso duplicaría conceptos y no coincide con el esquema base ya construido.

Relación propuesta:

```text
organizaciones
   └── manzanas_vigiared
          └── unidades (domicilios)
                 ├── membresias_unidad
                 ├── credenciales_domicilio
                 └── solicitudes_ingreso
```

Para evitar colisión semántica con la tabla heredada, la columna nueva de `unidades` debe llamarse `manzana_vigiared_id uuid`, no `manzana_id`.

Restricción propuesta:

- FK compuesta `(organizacion_id, manzana_vigiared_id)` → `manzanas_vigiared(organizacion_id, id)`.
- Una unidad pertenece a una sola manzana VIGIARED.
- Una manzana contiene muchas unidades/domicilios.
- Una manzana pertenece a una sola organización en esta versión.
- Una organización puede tener muchas manzanas.
- La relación debe ser explícita; no se deduce de dirección, localidad ni nombre.

## 5. QR y PIN de domicilio

Se conserva sin cambios la decisión funcional aprobada:

- El QR contiene sólo el identificador público de la manzana (o una URL que lo transporta); no contiene PIN ni datos personales.
- El PIN se genera en servidor para cada unidad/domicilio y se almacena como HMAC con secreto servidor.
- El QR abre la pantalla de incorporación y permite identificar la manzana.
- El vecino introduce el PIN de su domicilio; el backend resuelve la unidad y crea una solicitud pendiente.
- Cada persona usa cuenta individual. El teléfono es requisito para uso vecinal; correo opcional.
- Una membresía activa es la autorización real para consultar información o recibir alertas. El PIN sólo permite solicitar incorporación.
- La aprobación de nuevos integrantes sigue el procedimiento de responsable/administrador autorizado.
- Rotar el PIN no revoca membresías ya aprobadas.

La entidad de credenciales propuesta es `credenciales_domicilio`, con referencia a `organizacion_id` y `unidad_id`, HMAC, estado y datos mínimos de emisión/revocación. No se registra el PIN en auditoría, URL ni logs.

## 6. Distribución de alertas derivada del modelo

Cuando se implemente el módulo de alertas:

1. El servidor valida cuenta y membresía activa del emisor en una unidad activa.
2. Obtiene la manzana desde `unidades.manzana_vigiared_id`.
3. Obtiene la organización desde la unidad y verifica que coincida con la manzana.
4. Crea una sola alerta operativa.
5. Selecciona las membresías activas de las unidades asociadas a esa misma `manzana_vigiared_id`.
6. Deduplica por usuario dentro de la manzana.
7. Excluye pendientes, suspendidas, revocadas y unidades no activas.
8. Centro de Monitoreo y vecinos hacen referencia al mismo ID de alerta.
9. Los vecinos reciben aviso mínimo, sin datos de identidad, dirección exacta, GPS, ficha médica ni texto libre.
10. Antes de cualquier despacho diferido se revalida la membresía.

No usar `public.manzanas`, `alertas.manzana` ni coincidencias de texto como fuente de autorización para la red VIGIARED.

## 7. Incompatibilidades adicionales encontradas en la migración borrador actual

Además de la colisión de nombres:

- La función `crear_domicilio_con_responsable` inserta `created_by` en `public.unidades`; el inventario del esquema base consultado no documenta esa columna. Debe verificarse en DDL real antes de referenciarla.
- La migración agrega `unidades.manzana_id`; la propuesta corregida usa `manzana_vigiared_id` para no confundir la relación nueva con la tabla heredada.
- La migración asume que la tabla `manzanas` nueva posee columnas y constraints que `CREATE TABLE IF NOT EXISTS` no agrega a una tabla preexistente.
- No ejecutar parcialmente la migración para “ver qué pasa”: debe revisarse y ensayarse completa en una base desechable.

La migración actual queda **bloqueada y supersedida como borrador de diseño** hasta que se prepare una versión corregida y se pruebe de punta a punta. No se ha ejecutado en el Supabase compartido.

## 8. Plan de implementación seguro

1. La inspección de columnas, constraints, índices, RLS y triggers del proyecto compartido ya fue ejecutada en modo solo lectura; falta confirmar el resultado de `pg_policies`.
2. La migración corregida se prepara en una rama aislada y se ensaya en PostgreSQL 16 efímero con datos sintéticos.
3. La prueba incluye la FK compuesta para rechazar asociaciones entre organizaciones distintas.
4. Después se amplían las pruebas de QR público, PIN único por domicilio, rotación, solicitudes y límites de intentos.
5. Se revisan selección de audiencia, múltiples manzanas y organizaciones, y deduplicación por usuario.
6. Sólo después de superar pruebas y revisar el diff se solicitará autorización separada antes de tocar el proyecto Supabase compartido.

## 9. Estado

Este documento registra el modelo territorial y los hallazgos de compatibilidad confirmados. La corrección de la migración y de la Edge Function se está preparando en la rama `fix/vigiared-territorial-model-v0-3`. Los cambios permanecen fuera de Supabase real y producción; no se ejecutó SQL en el proyecto compartido, no se desplegó ninguna función y no se generaron costos.
