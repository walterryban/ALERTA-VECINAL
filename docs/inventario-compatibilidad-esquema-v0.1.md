# VIGIARED — Inventario de compatibilidad v0.1

Estado: revisión estática de borradores. No representa una inspección de la base Supabase real.

## Hallazgos que bloquean la migración

1. **Origen de alertas:** identidad v0.2 vincula membresías a `unidades.id`; difusión v0.1 agrega `alertas.manzana_id`. La relación canónica propuesta es `alertas.unidad_id uuid REFERENCES unidades(id)`. La RPC debe derivarla de la membresía autenticada, nunca recibirla como autoridad desde el navegador.
2. **Manzana duplicada:** no guardar `manzana_id` también en `difusiones_comunitarias`. Derivar manzana mediante alerta → unidad → establecimiento → manzana.
3. **Join temporal por texto:** RBAC v0.3 usa `alertas.manzana = manzanas.nombre_manzana`. Sustituirlo por FKs; los nombres no son identificadores.
4. **Identidad legada:** `vecinos` y `credenciales_integrantes` no deben autorizar accesos. La autoridad moderna será `perfiles_vecinales` y `membresias_vecinales`.
5. **Una sola fuente de alertas:** no crear un segundo almacén operativo hasta decidir, tras inspección de dependencias, si se conserva `public.alertas` o se migra íntegramente.
6. **Tipos y estados:** confirmar el tipo real de `alertas.id`; los borradores usan distintas convenciones de timestamps y catálogos.

## Modelo relacional propuesto

```text
auth.users → perfiles_vecinales → membresias_vecinales → unidades
unidades → establecimientos → manzanas → organizaciones_municipales
alertas.unidad_id → unidades.id
difusiones_comunitarias.alerta_id → alertas.id
entregas_notificacion_vecinal.membresia_id → membresias_vecinales.id
```

La organización se deriva de la manzana. No duplicar `organizacion_id` en unidades, alertas o difusiones. La pertenencia municipal única por manzana queda como decisión pendiente de confirmar.

## Orden de trabajo

1. Inspeccionar DDL real en un proyecto Supabase aislado: columnas, tipos, constraints, índices, triggers, vistas, grants y publicaciones Realtime.
2. Consolidar RBAC y asociación manzana-organización.
3. Consolidar establecimientos y unidades.
4. Consolidar identidad individual y membresías.
5. Añadir relación alerta-unidad y retirar joins por texto.
6. Consolidar difusión, entregas y outbox.
7. Implementar RLS, grants mínimos, RPC transaccionales y auditoría.
8. Ejecutar pruebas negativas de aislamiento, revocación, concurrencia y privacidad.

## Datos históricos y seguridad

Las manzanas y alertas actuales de prueba no se deben emparejar por nombre, teléfono ni dirección. Mantenerlas sin asociación nueva hasta definir una migración explícita. No exponer datos médicos en avisos comunitarios; el acceso COM a domicilio, contacto, GPS y ficha médica requiere permisos diferenciados y auditoría.

## Decisiones pendientes

- ¿Una manzana pertenece siempre a una sola organización?
- ¿Se conserva `public.alertas` como almacén único?
- ¿Qué roles COM pueden consultar domicilio, contacto y GPS?
- ¿Qué catálogo de tipos/estados reemplaza los valores heredados?
- ¿Cómo se excluyen unidades suspendidas o que no participan de la red?

**Límite:** este documento es análisis de archivos de desarrollo, no validación de Supabase. No se ejecutó SQL ni se modificaron datos o despliegues. No producir migración ejecutable hasta resolver las decisiones y verificar el DDL en entorno aislado.
