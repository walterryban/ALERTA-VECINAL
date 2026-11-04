-- ALERTA VECINAL PRO
-- RBAC v0.3: aislamiento de alertas y manzanas por organización
-- DEPENDE de RBAC v0.1 y v0.2.
-- BORRADOR: revisar y probar en proyecto aislado. No ejecutar en producción.
--
-- No asigna manzanas ficticias a municipalidades. El propietario las verá
-- globalmente; cada municipio verá solo manzanas asociadas a su organización.
-- Las alertas se vinculan por nombre_manzana mientras el modelo existente
-- conserve alertas.manzana como texto.

BEGIN;

CREATE OR REPLACE FUNCTION public.tiene_rol_municipal(
  p_organizacion_id uuid,
  p_roles text[]
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    p_organizacion_id IS NOT NULL
    AND p_roles IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.membresias_municipales AS m
      JOIN public.organizaciones_municipales AS o
        ON o.id = m.organizacion_id
      WHERE m.auth_user_id = auth.uid()
        AND m.organizacion_id = p_organizacion_id
        AND m.rol = ANY (p_roles)
        AND m.estado = 'activa'
        AND o.estado = 'activa'
    );
$$;

REVOKE ALL ON FUNCTION public.tiene_rol_municipal(uuid, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tiene_rol_municipal(uuid, text[]) TO authenticated;

-- Retirar políticas heredadas globales que autorizaban a cualquier email
-- listado en public.operadores a consultar todas las manzanas/alertas.
DROP POLICY IF EXISTS op_alertas_select ON public.alertas;
DROP POLICY IF EXISTS op_alertas_update ON public.alertas;
DROP POLICY IF EXISTS op_manzanas_all ON public.manzanas;

-- ALERTAS: propietario global; los perfiles municipales solo ven alertas
-- cuya manzana pertenece a una organización donde tienen membresía activa.
CREATE POLICY rbac_alertas_select
ON public.alertas
FOR SELECT
TO authenticated
USING (
  public.es_propietario_plataforma()
  OR EXISTS (
    SELECT 1
    FROM public.manzanas AS mz
    WHERE mz.nombre_manzana = alertas.manzana
      AND mz.organizacion_id IS NOT NULL
      AND public.tiene_rol_municipal(
        mz.organizacion_id,
        ARRAY[
          'administrador_municipal',
          'supervisor_municipal',
          'operador_municipal',
          'auditor_municipal'
        ]::text[]
      )
  )
);

-- Actualización operativa: auditor tiene lectura, no puede cambiar estados.
CREATE POLICY rbac_alertas_update
ON public.alertas
FOR UPDATE
TO authenticated
USING (
  public.es_propietario_plataforma()
  OR EXISTS (
    SELECT 1
    FROM public.manzanas AS mz
    WHERE mz.nombre_manzana = alertas.manzana
      AND mz.organizacion_id IS NOT NULL
      AND public.tiene_rol_municipal(
        mz.organizacion_id,
        ARRAY[
          'administrador_municipal',
          'supervisor_municipal',
          'operador_municipal'
        ]::text[]
      )
  )
)
WITH CHECK (
  public.es_propietario_plataforma()
  OR EXISTS (
    SELECT 1
    FROM public.manzanas AS mz
    WHERE mz.nombre_manzana = alertas.manzana
      AND mz.organizacion_id IS NOT NULL
      AND public.tiene_rol_municipal(
        mz.organizacion_id,
        ARRAY[
          'administrador_municipal',
          'supervisor_municipal',
          'operador_municipal'
        ]::text[]
      )
  )
);

-- MANZANAS: lectura por pertenencia; altas y cambios solo propietario/admin.
CREATE POLICY rbac_manzanas_select
ON public.manzanas
FOR SELECT
TO authenticated
USING (
  public.es_propietario_plataforma()
  OR public.tiene_rol_municipal(
    organizacion_id,
    ARRAY[
      'administrador_municipal',
      'supervisor_municipal',
      'operador_municipal',
      'auditor_municipal'
    ]::text[]
  )
);

CREATE POLICY rbac_manzanas_insert
ON public.manzanas
FOR INSERT
TO authenticated
WITH CHECK (
  organizacion_id IS NOT NULL
  AND (
    (
      public.es_propietario_plataforma()
      AND EXISTS (
        SELECT 1 FROM public.organizaciones_municipales AS o
        WHERE o.id = organizacion_id AND o.estado = 'activa'
      )
    )
    OR public.tiene_rol_municipal(
      organizacion_id,
      ARRAY['administrador_municipal']::text[]
    )
  )
);

CREATE POLICY rbac_manzanas_update
ON public.manzanas
FOR UPDATE
TO authenticated
USING (
  public.es_propietario_plataforma()
  OR public.tiene_rol_municipal(
    organizacion_id,
    ARRAY['administrador_municipal']::text[]
  )
)
WITH CHECK (
  organizacion_id IS NOT NULL
  AND (
    (
      public.es_propietario_plataforma()
      AND EXISTS (
        SELECT 1 FROM public.organizaciones_municipales AS o
        WHERE o.id = organizacion_id AND o.estado = 'activa'
      )
    )
    OR public.tiene_rol_municipal(
      organizacion_id,
      ARRAY['administrador_municipal']::text[]
    )
  )
);

-- No se crea política DELETE: las manzanas no se eliminan desde el COM.
-- Para retirar una manzana se deberá implementar baja lógica auditada.

COMMIT;

-- PRUEBAS OBLIGATORIAS EN PROYECTO AISLADO:
-- 1. Propietario ve todas las manzanas/alertas y puede crear manzanas
--    únicamente asociándolas a una organización activa.
-- 2. Admin municipal A no puede consultar/actualizar recursos de B.
-- 3. Supervisor y operador pueden consultar y actualizar alertas propias.
-- 4. Auditor solo puede consultar alertas/manzanas propias.
-- 5. Ningún usuario municipal ve manzanas sin organización_id.
-- 6. Usuario Auth sin membresía no ve filas.
-- 7. La función crear_alerta SECURITY DEFINER continúa insertando alertas.
-- 8. Los usuarios listados solo en public.operadores no conservan acceso
--    automáticamente: deben recibir una membresía explícita.
--
-- NOTA: esta política de alertas depende de que nombre_manzana sea único
-- globalmente (actualmente lo es en la tabla manzanas). La siguiente mejora
-- debe añadir alertas.manzana_id y migrar el vínculo sin inferir datos reales.
