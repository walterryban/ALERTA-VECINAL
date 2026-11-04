-- AVISO: ESTE BORRADOR RPC V0.1 QUEDÓ SUPERSEDIDO.
-- NO EJECUTAR NI CONECTAR. Usar como referencia histórica únicamente.
-- Las RPC corregidas forman parte de docs/migracion-identidad-vecinal-v0.2-borrador.sql.
-- V0.1 depende del modelo anterior vinculado a public.vecinos.

-- VIGIARED
-- RPC DE INVITACION Y SOLICITUD DE INGRESO v0.1
-- BORRADOR PARCIAL: NO EJECUTAR / NO DESPLEGAR.
-- Dependencias:
--   migracion-red-comunitaria-v0.1-borrador.sql
--   migracion-identidad-vecinal-v0.1-borrador.sql
--
-- Implementa solo emisión de invitación por titular ya activo y canje
-- transaccional de un token de un solo uso.
-- NO activa membresías ni resuelve todavía el alta definitiva en public.vecinos.
-- Requiere proyecto Supabase aislado, revisión y pruebas de concurrencia.

BEGIN;

CREATE TABLE IF NOT EXISTS public.solicitudes_ingreso_vecinales (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  unidad_id uuid NOT NULL REFERENCES public.unidades(id) ON DELETE RESTRICT,
  nombre_declarado text NOT NULL CHECK (pg_catalog.length(pg_catalog.btrim(nombre_declarado)) BETWEEN 2 AND 120),
  telefono_declarado text NOT NULL CHECK (pg_catalog.length(pg_catalog.btrim(telefono_declarado)) BETWEEN 6 AND 40),
  estado text NOT NULL DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente', 'aprobada', 'rechazada', 'cancelada')),
  creada_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  revisada_at timestamptz,
  revisada_por uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  motivo_revision text
);

CREATE INDEX IF NOT EXISTS solicitudes_ingreso_vecinales_unidad_estado_idx
  ON public.solicitudes_ingreso_vecinales (unidad_id, estado, creada_at DESC);
CREATE INDEX IF NOT EXISTS solicitudes_ingreso_vecinales_usuario_idx
  ON public.solicitudes_ingreso_vecinales (auth_user_id, creada_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS solicitudes_ingreso_vecinales_pendiente_uk
  ON public.solicitudes_ingreso_vecinales (auth_user_id, unidad_id)
  WHERE estado = 'pendiente';

ALTER TABLE public.solicitudes_ingreso_vecinales ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON TABLE public.solicitudes_ingreso_vecinales
  FROM PUBLIC, anon, authenticated;

-- Emite token de 256 bits, lo almacena solo como SHA-256 y lo devuelve
-- una sola vez. El titular debe tener membresía activa en esa unidad.
CREATE OR REPLACE FUNCTION public.emitir_invitacion_vecinal(
  p_unidad_id uuid,
  p_vigencia_horas integer DEFAULT 24
)
RETURNS text
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_raw text;
  v_hash bytea;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Sesión requerida' USING ERRCODE = '42501';
  END IF;

  IF p_unidad_id IS NULL OR p_vigencia_horas IS NULL
     OR p_vigencia_horas < 1 OR p_vigencia_horas > 72 THEN
    RAISE EXCEPTION 'Solicitud inválida' USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.membresias_vecinales AS m
    JOIN public.unidades AS u ON u.id = m.unidad_id
    JOIN public.establecimientos AS e ON e.id = u.establecimiento_id
    WHERE m.auth_user_id = v_actor
      AND m.unidad_id = p_unidad_id
      AND m.rol = 'titular'
      AND m.estado = 'activa'
      AND u.estado = 'activo'
      AND e.estado = 'activo'
  ) THEN
    RAISE EXCEPTION 'No autorizado para esta unidad' USING ERRCODE = '42501';
  END IF;

  -- Límite básico: 10 invitaciones emitidas por actor en la última hora.
  IF (
    SELECT pg_catalog.count(*)
    FROM public.auditoria_vecinal AS a
    WHERE a.actor_auth_user_id = v_actor
      AND a.accion = 'invitacion_emitida'
      AND a.creado_at > pg_catalog.now() - interval '1 hour'
      AND a.resultado = 'exito'
  ) >= 10 THEN
    RAISE EXCEPTION 'Límite de invitaciones alcanzado' USING ERRCODE = '54000';
  END IF;

  v_raw := pg_catalog.translate(
    pg_catalog.rtrim(
      pg_catalog.replace(
        pg_catalog.replace(
          pg_catalog.encode(extensions.gen_random_bytes(32), 'base64'),
          E'\\n', ''
        ),
        '+', '-'
      ),
      '='
    ),
    '/', '_'
  );
  v_hash := extensions.digest(pg_catalog.convert_to(v_raw, 'UTF8'), 'sha256');

  INSERT INTO public.invitaciones_vecinales (
    unidad_id, token_hash, emitida_por, expira_at
  ) VALUES (
    p_unidad_id, v_hash, v_actor,
    pg_catalog.now() + pg_catalog.make_interval(hours => p_vigencia_horas)
  );

  INSERT INTO public.auditoria_vecinal (
    actor_auth_user_id, unidad_id, accion, resultado
  ) VALUES (v_actor, p_unidad_id, 'invitacion_emitida', 'exito');

  RETURN v_raw;
END;
$$;

-- Canjea invitación con bloqueo de fila. No activa membresía: crea
-- solicitud pendiente y consume el token en la misma transacción.
CREATE OR REPLACE FUNCTION public.solicitar_ingreso_vecinal(
  p_token text,
  p_nombre text,
  p_telefono text
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_inv public.invitaciones_vecinales%ROWTYPE;
  v_request_id uuid;
  v_hash bytea;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Sesión requerida' USING ERRCODE = '42501';
  END IF;

  IF p_token IS NULL OR pg_catalog.length(p_token) < 40
     OR pg_catalog.length(p_token) > 100
     OR p_nombre IS NULL OR pg_catalog.length(pg_catalog.btrim(p_nombre)) NOT BETWEEN 2 AND 120
     OR p_telefono IS NULL OR pg_catalog.length(pg_catalog.btrim(p_telefono)) NOT BETWEEN 6 AND 40 THEN
    RAISE EXCEPTION 'Invitación o datos inválidos' USING ERRCODE = '22023';
  END IF;

  v_hash := extensions.digest(pg_catalog.convert_to(p_token, 'UTF8'), 'sha256');

  SELECT i.* INTO v_inv
  FROM public.invitaciones_vecinales AS i
  WHERE i.token_hash = v_hash
  FOR UPDATE;

  IF NOT FOUND
     OR v_inv.usos <> 0
     OR v_inv.revocada_at IS NOT NULL
     OR v_inv.expira_at <= pg_catalog.now() THEN
    RAISE EXCEPTION 'Invitación inválida o vencida' USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.membresias_vecinales AS m
    WHERE m.auth_user_id = v_actor
      AND m.unidad_id = v_inv.unidad_id
      AND m.estado = 'activa'
  ) THEN
    RAISE EXCEPTION 'La cuenta ya pertenece a esta unidad' USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.solicitudes_ingreso_vecinales (
    auth_user_id, unidad_id, nombre_declarado, telefono_declarado
  ) VALUES (
    v_actor, v_inv.unidad_id,
    pg_catalog.btrim(p_nombre), pg_catalog.btrim(p_telefono)
  )
  RETURNING id INTO v_request_id;

  UPDATE public.invitaciones_vecinales
  SET usos = 1, usada_at = pg_catalog.now()
  WHERE id = v_inv.id;

  INSERT INTO public.auditoria_vecinal (
    actor_auth_user_id, unidad_id, accion, resultado
  ) VALUES (v_actor, v_inv.unidad_id, 'solicitud_ingreso', 'exito');

  RETURN v_request_id;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'Ya existe una solicitud pendiente para esta unidad' USING ERRCODE = '23505';
END;
$$;

REVOKE ALL ON FUNCTION public.emitir_invitacion_vecinal(uuid, integer)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.solicitar_ingreso_vecinal(text, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.emitir_invitacion_vecinal(uuid, integer)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.solicitar_ingreso_vecinal(text, text, text)
  TO authenticated;

COMMIT;

-- BLOQUEANTES ANTES DE USO:
-- 1. Definir y auditar el alta del primer titular (no existe bootstrap aún).
-- 2. Diseñar aprobación/rechazo y alta canónica de integrante sin confiar
--    en nombre/teléfono declarados por el cliente.
-- 3. Añadir verificación de teléfono/identidad y límites anti-enumeración.
-- 4. Revisar consumo de invitación si falla la creación de solicitud.
-- 5. Probar concurrencia, token repetido, expiración, revocación y rate limits.
-- 6. Confirmar que todas las funciones SECURITY DEFINER tengan propietario
--    confiable, permisos mínimos y configuración segura en el proyecto aislado.
