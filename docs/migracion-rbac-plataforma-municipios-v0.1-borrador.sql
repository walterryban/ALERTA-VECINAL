-- ALERTA VECINAL PRO
-- RBAC: PROPIETARIO DE PLATAFORMA + ADMINISTRACION MUNICIPAL
-- BORRADOR ADITIVO / NO EJECUTAR EN PRODUCCION
-- Fecha: 2026-11-04
--
-- Alcance de esta fase:
--   * Crear catálogo privado de organizaciones y membresías municipales.
--   * Crear registro privado de propietarios de plataforma.
--   * Agregar vínculo opcional de manzanas a organización.
--   * Crear predicados SECURITY DEFINER de solo comprobación.
--
-- No hace:
--   * No crea usuarios Auth ni envía invitaciones.
--   * No eleva automáticamente los correos de public.operadores.
--   * No modifica public.es_operador(), sus grants ni las políticas actuales.
--   * No cambia alertas/manzanas existentes ni asigna organizaciones.
--   * No crea administradores ni propietarios.
--
-- IMPORTANTE: hasta sustituir las políticas/RPC heredadas, este catálogo
-- NO aplica por sí solo aislamiento multi-municipal sobre alertas/manzanas.
-- Revisar en proyecto Supabase aislado, hacer backup y aprobar expresamente.

BEGIN;

CREATE TABLE IF NOT EXISTS public.organizaciones_municipales (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  nombre text NOT NULL,
  codigo text NOT NULL UNIQUE,
  estado text NOT NULL DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente', 'activa', 'suspendida', 'inactiva')),
  creada_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  actualizada_at timestamptz NOT NULL DEFAULT pg_catalog.now()
);

CREATE TABLE IF NOT EXISTS public.propietarios_plataforma (
  auth_user_id uuid PRIMARY KEY
    REFERENCES auth.users(id) ON DELETE RESTRICT,
  activo boolean NOT NULL DEFAULT true,
  creado_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  creado_por uuid REFERENCES auth.users(id) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS public.membresias_municipales (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  organizacion_id uuid NOT NULL
    REFERENCES public.organizaciones_municipales(id) ON DELETE RESTRICT,
  auth_user_id uuid NOT NULL
    REFERENCES auth.users(id) ON DELETE RESTRICT,
  rol text NOT NULL CHECK (rol IN (
    'administrador_municipal',
    'supervisor_municipal',
    'operador_municipal',
    'auditor_municipal'
  )),
  estado text NOT NULL DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente', 'activa', 'suspendida', 'revocada')),
  creada_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  creada_por uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  actualizada_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  UNIQUE (organizacion_id, auth_user_id)
);

CREATE INDEX IF NOT EXISTS membresias_municipales_auth_user_idx
  ON public.membresias_municipales (auth_user_id);
CREATE INDEX IF NOT EXISTS membresias_municipales_org_rol_estado_idx
  ON public.membresias_municipales (organizacion_id, rol, estado);

-- Vínculo opcional: no se asignan manzanas ficticias automáticamente.
ALTER TABLE public.manzanas
  ADD COLUMN IF NOT EXISTS organizacion_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint
    WHERE conname = 'manzanas_organizacion_id_fkey'
      AND conrelid = 'public.manzanas'::regclass
  ) THEN
    ALTER TABLE public.manzanas
      ADD CONSTRAINT manzanas_organizacion_id_fkey
      FOREIGN KEY (organizacion_id)
      REFERENCES public.organizaciones_municipales(id)
      ON DELETE RESTRICT;
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS manzanas_organizacion_id_idx
  ON public.manzanas (organizacion_id);

-- Sin políticas de lectura/escritura directa: el acceso futuro será por RPC
-- con validación de auth.uid(), rol y organización.
ALTER TABLE public.organizaciones_municipales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.propietarios_plataforma ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.membresias_municipales ENABLE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES ON TABLE
  public.organizaciones_municipales,
  public.propietarios_plataforma,
  public.membresias_municipales
FROM PUBLIC, anon, authenticated;

-- Predicado global: una fila activa, cargada por procedimiento administrativo
-- controlado, identifica al propietario. No existe auto-registro.
CREATE OR REPLACE FUNCTION public.es_propietario_plataforma()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.propietarios_plataforma AS p
    WHERE p.auth_user_id = auth.uid()
      AND p.activo = true
  );
$$;

-- Predicado municipal: verifica membresía activa y rol de administrador
-- dentro de la organización solicitada. No concede por sí solo acceso a tablas.
CREATE OR REPLACE FUNCTION public.es_administrador_municipal(p_organizacion_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.membresias_municipales AS m
    JOIN public.organizaciones_municipales AS o
      ON o.id = m.organizacion_id
    WHERE m.auth_user_id = auth.uid()
      AND m.organizacion_id = p_organizacion_id
      AND m.rol = 'administrador_municipal'
      AND m.estado = 'activa'
      AND o.estado = 'activa'
  );
$$;

REVOKE ALL ON FUNCTION public.es_propietario_plataforma() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.es_administrador_municipal(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.es_propietario_plataforma() TO authenticated;
GRANT EXECUTE ON FUNCTION public.es_administrador_municipal(uuid) TO authenticated;

COMMIT;

-- VERIFICACION SOLO LECTURA (ejecutar por separado tras aplicar en entorno aislado):
-- SELECT table_name, column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema = 'public'
--   AND table_name IN (
--     'organizaciones_municipales',
--     'propietarios_plataforma',
--     'membresias_municipales',
--     'manzanas'
--   )
-- ORDER BY table_name, ordinal_position;
--
-- SELECT c.relname, c.relrowsecurity
-- FROM pg_catalog.pg_class AS c
-- JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
-- WHERE n.nspname = 'public'
--   AND c.relname IN (
--     'organizaciones_municipales',
--     'propietarios_plataforma',
--     'membresias_municipales'
--   )
-- ORDER BY c.relname;
--
-- NOTA: revisar también privilegios heredados, membresías de roles, políticas
-- preexistentes y las definiciones/grants de todas las RPC antes de producción.
