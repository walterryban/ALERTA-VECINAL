-- ALERTA VECINAL PRO
-- MIGRACION ADITIVA v0.1 — SOLO BORRADOR / NO EJECUTAR EN PRODUCCION
-- Fecha: 2026-11-04
--
-- IMPORTANTE:
-- * Las manzanas y alertas existentes son DATOS FICTICIOS DE PRUEBA.
-- * Este archivo NO inserta domicilios, personas, comercios ni alertas.
-- * No modifica ni elimina registros existentes.
-- * No cambia las tablas alertas, manzanas, vendedores ni operadores.
-- * No crea credenciales en texto plano ni reutiliza el PIN compartido.
-- * Requiere revisión del esquema real y prueba en un proyecto Supabase aislado.
--
-- Modelo:
--   manzanas (existente, id bigint)
--     -> establecimientos (predios/direcciones)
--       -> unidades (vivienda, depto., habitación, local, etc.)
--         -> vecinos (personas existentes, vínculo opcional)
--           -> credenciales_integrantes (hash de token individual)
--
-- La emisión/validación/revocación de credenciales NO está implementada
-- por este SQL. Se hará mediante RPC seguras después de revisar roles,
-- autenticación, rate limits, auditoría y el mecanismo de generación aleatoria.
--
-- No ejecutar hasta:
-- 1. Exportar backup y probar en un proyecto Supabase desechable.
-- 2. Confirmar que manzanas.id sigue siendo bigint y vecinos.id uuid.
-- 3. Confirmar que no existen objetos con estos nombres.
-- 4. Revisar el plan de permisos/RLS y aprobar expresamente su aplicación.

BEGIN;

CREATE TABLE IF NOT EXISTS public.establecimientos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  manzana_id bigint NOT NULL
    REFERENCES public.manzanas(id) ON DELETE RESTRICT,
  direccion text NOT NULL,
  referencia text,
  tipo text NOT NULL CHECK (tipo IN (
    'vivienda_unica',
    'vivienda_con_departamentos',
    'edificio_residencial',
    'comercio',
    'galeria_comercial',
    'pension_residencia_hostel',
    'complejo_habitacional',
    'uso_mixto',
    'otro'
  )),
  estado text NOT NULL DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente', 'activo', 'suspendido', 'inactivo')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS establecimientos_manzana_id_idx
  ON public.establecimientos (manzana_id);
CREATE INDEX IF NOT EXISTS establecimientos_estado_idx
  ON public.establecimientos (estado);

CREATE TABLE IF NOT EXISTS public.unidades (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  establecimiento_id uuid NOT NULL
    REFERENCES public.establecimientos(id) ON DELETE RESTRICT,
  tipo text NOT NULL CHECK (tipo IN (
    'vivienda',
    'departamento',
    'habitacion',
    'local',
    'oficina',
    'puesto',
    'sector',
    'otro'
  )),
  identificador text NOT NULL,
  piso text,
  participa_red boolean NOT NULL DEFAULT false,
  estado text NOT NULL DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente', 'activo', 'suspendido', 'inactivo')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT unidades_establecimiento_identificador_uk
    UNIQUE (establecimiento_id, identificador)
);

CREATE INDEX IF NOT EXISTS unidades_establecimiento_id_idx
  ON public.unidades (establecimiento_id);
CREATE INDEX IF NOT EXISTS unidades_estado_idx
  ON public.unidades (estado);

-- La columna es nullable para no romper personas históricas ni de prueba.
ALTER TABLE public.vecinos
  ADD COLUMN IF NOT EXISTS unidad_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'vecinos_unidad_id_fkey'
      AND conrelid = 'public.vecinos'::regclass
  ) THEN
    ALTER TABLE public.vecinos
      ADD CONSTRAINT vecinos_unidad_id_fkey
      FOREIGN KEY (unidad_id)
      REFERENCES public.unidades(id)
      ON DELETE RESTRICT;
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS vecinos_unidad_id_idx
  ON public.vecinos (unidad_id);

-- Solo se almacena el hash de un token aleatorio de alta entropía.
-- El token original se muestra/entrega una sola vez por un flujo seguro
-- que todavía debe diseñarse e implementarse.
CREATE TABLE IF NOT EXISTS public.credenciales_integrantes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  integrante_id uuid NOT NULL
    REFERENCES public.vecinos(id) ON DELETE RESTRICT,
  token_hash text NOT NULL UNIQUE,
  estado text NOT NULL DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente', 'activa', 'revocada', 'expirada')),
  intentos_fallidos integer NOT NULL DEFAULT 0
    CHECK (intentos_fallidos >= 0),
  bloqueada_hasta timestamptz,
  expira_at timestamptz,
  creada_at timestamptz NOT NULL DEFAULT now(),
  ultimo_uso_at timestamptz,
  revocada_at timestamptz,
  revocada_por uuid
);

CREATE INDEX IF NOT EXISTS credenciales_integrantes_integrante_id_idx
  ON public.credenciales_integrantes (integrante_id);
CREATE INDEX IF NOT EXISTS credenciales_integrantes_estado_idx
  ON public.credenciales_integrantes (estado);

-- Sin acceso directo desde navegador. Las futuras RPC deberán comprobar
-- identidad, rol, alcance y estado antes de leer o modificar estos datos.
ALTER TABLE public.establecimientos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.unidades ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.credenciales_integrantes ENABLE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES ON TABLE
  public.establecimientos,
  public.unidades,
  public.credenciales_integrantes
FROM PUBLIC, anon, authenticated;

COMMIT;

-- VERIFICACION SOLO LECTURA (ejecutar por separado después de una prueba):
-- SELECT table_name, column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema = 'public'
--   AND table_name IN (
--     'establecimientos', 'unidades', 'vecinos',
--     'credenciales_integrantes'
--   )
-- ORDER BY table_name, ordinal_position;
--
-- SELECT c.relname, c.relrowsecurity
-- FROM pg_class c
-- JOIN pg_namespace n ON n.oid = c.relnamespace
-- WHERE n.nspname = 'public'
--   AND c.relname IN (
--     'establecimientos', 'unidades', 'credenciales_integrantes'
--   )
-- ORDER BY c.relname;
