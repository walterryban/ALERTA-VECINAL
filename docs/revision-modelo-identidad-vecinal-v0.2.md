# VIGIARED — Corrección del modelo de identidad vecinal v0.2

Estado: decisión de arquitectura recomendada. No es una migración ejecutable.

## Hallazgo crítico

El borrador v0.1 vincula `membresias_vecinales` a `public.vecinos` mediante la pareja `(integrante_id, unidad_id)`, y agrega un índice único sobre `vecinos.auth_user_id`.

Ese diseño acopla la identidad de una persona a una sola unidad. No representa correctamente los casos en los que una misma persona puede estar autorizada en más de una unidad (por ejemplo, propietario que vive en un departamento y administra un local, cuidador autorizado en dos domicilios o una persona que participa en dos establecimientos).

También mezcla el registro histórico `public.vecinos` —que contiene el modelo legado de PIN compartido y datos de prueba— con la identidad autenticada moderna.

**Decisión:** no ejecutar ni conectar las RPC de aprobación v0.1 hasta corregir este vínculo.

## Modelo recomendado

Separar tres conceptos:

1. **Cuenta:** `auth.users`, credencial de acceso individual.
2. **Perfil de persona:** una identidad de plataforma, independiente de las unidades a las que pertenece. Una cuenta puede tener un perfil.
3. **Membresía:** autorización de ese perfil en una unidad específica, con rol y estado propios.

Relaciones objetivo:

```text
auth.users (1) ─── (0..1) perfiles_vecinales
                           |
                           | 1
                           |
                           | N
                    membresias_vecinales
                           |
                           | N
                           |
                           | 1
                        unidades
```

- `perfiles_vecinales.auth_user_id` es único.
- `membresias_vecinales` referencia `perfil_id` y `unidad_id`, no una fila de `vecinos`.
- La unicidad es por `(perfil_id, unidad_id)`; la misma persona puede tener membresías en unidades diferentes.
- La ficha heredada `public.vecinos` puede mantenerse como dato histórico/operativo durante la transición, pero no debe ser la fuente de autorización.
- No se migran automáticamente filas de vecinos ficticias ni se deduce identidad por coincidencia de nombre, teléfono o domicilio.

## Consecuencias para los borradores v0.1

- `migracion-identidad-vecinal-v0.1-borrador.sql`: requiere nueva versión antes de ejecutarse.
- `migracion-rpc-aprobacion-revocacion-vecinal-v0.1-borrador.sql`: queda en revisión; sus funciones que esperan `integrante_id` vinculado a `vecinos` no deben conectarse.
- `mi_contexto_vecinal()` debe devolver `perfil_id` y membresías activas, sin exponer identificadores de otras personas.
- Aprobación debe comprobar que la solicitud corresponde al mismo perfil autenticado y unidad, no que un navegador haya declarado nombre/teléfono.
- Revocación se aplica a una membresía concreta; no elimina ni bloquea la cuenta global de la persona.

## Flujo de alta corregido

1. La persona se autentica con su cuenta individual.
2. Un backend confiable crea o recupera su perfil, asociado a `auth.uid()`.
3. La invitación de un solo uso crea una solicitud pendiente para una unidad.
4. Un titular activo aprueba la solicitud.
5. La membresía vincula el perfil a esa unidad; no se duplica el perfil al ingresar a otra unidad.
6. Revocar una membresía no revoca otras unidades ni la cuenta Auth.

## Alta del primer titular

No debe existir autoasignación por QR, dirección, nombre, teléfono ni conocimiento del código de manzana. El primer titular requiere verificación fuera de banda por un procedimiento autorizado y auditado. La operación de bootstrap debe comprobar que el establecimiento y la unidad estén activos y que no exista ya un titular activo. La cuenta objetivo debe estar confirmada en Auth.

## Pruebas nuevas obligatorias

- Una misma cuenta puede tener perfil único y membresías aprobadas en dos unidades distintas.
- Revocar su membresía en unidad A no afecta unidad B.
- No se crea un segundo perfil para la misma cuenta.
- No se vinculan automáticamente vecinos históricos/ficticios.
- No se puede crear una membresía con perfil de otra cuenta.
- No se puede aprobar una solicitud de otra unidad.
- El primer titular solo puede ser inicializado mediante procedimiento de verificación autorizado.
- Los datos de una unidad no se devuelven al consultar el contexto de otra membresía no autorizada.

## Estado de seguridad

Hasta que exista la nueva versión del esquema, la terminal vecinal sigue utilizando el flujo legado de manzana/PIN y no debe considerarse lista para usuarios reales. No se modifica producción ni se ejecuta SQL como parte de esta revisión.
