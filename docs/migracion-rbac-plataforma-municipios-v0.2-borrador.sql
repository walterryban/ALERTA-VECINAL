-- ALERTA VECINAL PRO
-- RBAC v0.2: contexto, autorización de gestión y auditoría
-- DEPENDE de migracion-rbac-plataforma-municipios-v0.1-borrador.sql
-- BORRADOR / NO EJECUTAR HASTA REVISIÓN Y PRUEBA AISLADA.
--
-- Esta migración NO cambia las políticas heredadas de alertas/manzanas.
-- No habilita todavía el COM multi-municipal. El aislamiento de datos
-- requiere una migración posterior de políticas y RPC operativas.

BEGIN;

ALTER TABLE public.membresias_municipales
  ADD COLUMN IF NOT EXISTS email text;

CREATE TABLE IF NOT EXISTS public.auditoria_administrativa (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  organizacion_id uuid
    REFERENCES public.organizaciones_municipales(id) ON DELETE RESTRICT,
  actor_auth_user_id uuid NOT NULL
    REFERENCES auth.users(id) ON DELETE RESTRICT,
  objetivo_auth_user_id uuid
    REFERENCES auth.users(id) ON DELETE RESTRICT,
  accion text NOT NULL CHECK (accion IN (
    'organizacion_creada',
    'invitacion_enviada',
    'membresia_activada',
    'membresia_revocada',
    'rol_modificado'
  )),
  detalle jsonb NOT NULL DEFAULT '{}'::jsonb,
  creado_at timestamptz NOT NULL DEFAULT pg_catalog.now()
);

CREATE INDEX IF NOT EXISTS auditoria_administrativa_org_fecha_idx
  ON public.auditoria_administrativa (organizacion_id, creado_at DESC);
CREATE INDEX IF NOT EXISTS auditoria_administrativa_actor_fecha_idx
  ON public.auditoria_administrativa (actor_auth_user_id, creado_at DESC);

ALTER TABLE public.auditoria_administrativa ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON TABLE public.auditoria_administrativa
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.obtener_contexto_administrativo()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE
    WHEN public.es_propietario_plataforma() THEN
      jsonb_build_object(
        'es_propietario', true,
        'organizaciones', COALESCE((
          SELECT jsonb_agg(
            jsonb_build_object('id', o.id, 'nombre', o.nombre, 'codigo', o.codigo, 'estado', o.estado)
            ORDER BY o.nombre
          )
          FROM public.organizaciones_municipales AS o
        ), '[]'::jsonb)
      )
    ELSE
      jsonb_build_object(
        'es_propietario', false,
        'organizaciones', COALESCE((
          SELECT jsonb_agg(
            jsonb_build_object('id', o.id, 'nombre', o.nombre, 'codigo', o.codigo, 'estado', o.estado,
                               'rol', m.rol)
            ORDER BY o.nombre
          )
          FROM public.membresias_municipales AS m
          JOIN public.organizaciones_municipales AS o
            ON o.id = m.organizacion_id
          WHERE m.auth_user_id = auth.uid()
            AND m.estado = 'activa'
            AND o.estado = 'activa'
        ), '[]'::jsonb)
      )
  END;
$$;

CREATE OR REPLACE FUNCTION public.puede_gestionar_membresias(
  p_organizacion_id uuid,
  p_rol_objetivo text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    p_organizacion_id IS NOT NULL
    AND p_rol_objetivo IN (
      'administrador_municipal',
      'supervisor_municipal',
      'operador_municipal',
      'auditor_municipal'
    )
    AND (
      public.es_propietario_plataforma()
      OR (
        p_rol_objetivo <> 'administrador_municipal'
        AND EXISTS (
          SELECT 1
          FROM public.membresias_municipales AS m
          JOIN public.organizaciones_municipales AS o
            ON o.id = m.organizacion_id
          WHERE m.auth_user_id = auth.uid()
            AND m.organizacion_id = p_organizacion_id
            AND m.rol = 'administrador_municipal'
            AND m.estado = 'activa'
            AND o.estado = 'activa'
        )
      )
    );
$$;

REVOKE ALL ON FUNCTION public.obtener_contexto_administrativo() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.puede_gestionar_membresias(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.obtener_contexto_administrativo() TO authenticated;
GRANT EXECUTE ON FUNCTION public.puede_gestionar_membresias(uuid, text) TO authenticated;

COMMIT;

-- Verificación posterior (solo lectura):
-- SELECT proname, prosecdef, proconfig
-- FROM pg_catalog.pg_proc p
-- JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname = 'public'
--   AND proname IN (
--     'es_propietario_plataforma',
--     'es_administrador_municipal',
--     'obtener_contexto_administrativo',
--     'puede_gestionar_membresias'
--   )
-- ORDER BY proname;
--
-- SELECT relname, relrowsecurity
-- FROM pg_catalog.pg_class c
-- JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
-- WHERE n.nspname = 'public' AND relname = 'auditoria_administrativa';
