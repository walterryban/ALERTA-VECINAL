-- VIGIARED — APROBACION, REVOCACION Y CONTEXTO VECINAL v0.1
-- BORRADOR PARA REVISION / NO EJECUTAR NI DESPLEGAR.
-- Dependencias: migraciones red-comunitaria, identidad y RPC invitaciones.
-- La creación/vinculación inicial de public.vecinos debe ocurrir solo por
-- backend de confianza tras verificación de identidad. Nunca desde el cliente.

BEGIN;

-- Vínculo único entre ficha vecinal verificada y cuenta Auth.
-- Las filas históricas/ficticias quedan NULL; no se asignan automáticamente.
ALTER TABLE public.vecinos
  ADD COLUMN IF NOT EXISTS auth_user_id uuid
  REFERENCES auth.users(id) ON DELETE RESTRICT;

CREATE UNIQUE INDEX IF NOT EXISTS vecinos_auth_user_id_uk
  ON public.vecinos(auth_user_id)
  WHERE auth_user_id IS NOT NULL;

-- Aprobación: solo titular activo de la unidad puede aprobar.
-- p_integrante_id debe ser una ficha creada/vinculada por backend confiable
-- y debe pertenecer al auth_user_id que originó la solicitud.
CREATE OR REPLACE FUNCTION public.aprobar_ingreso_vecinal(
  p_solicitud_id uuid,
  p_integrante_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_req public.solicitudes_ingreso_vecinales%ROWTYPE;
  v_membership_id uuid;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Sesión requerida' USING ERRCODE = '42501';
  END IF;
  IF p_solicitud_id IS NULL OR p_integrante_id IS NULL THEN
    RAISE EXCEPTION 'Solicitud inválida' USING ERRCODE = '22023';
  END IF;

  SELECT s.* INTO v_req
  FROM public.solicitudes_ingreso_vecinales AS s
  WHERE s.id = p_solicitud_id
  FOR UPDATE;

  IF NOT FOUND OR v_req.estado <> 'pendiente' THEN
    RAISE EXCEPTION 'Solicitud no disponible' USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.membresias_vecinales AS m
    JOIN public.unidades AS u ON u.id = m.unidad_id
    JOIN public.establecimientos AS e ON e.id = u.establecimiento_id
    WHERE m.auth_user_id = v_actor
      AND m.unidad_id = v_req.unidad_id
      AND m.rol = 'titular'
      AND m.estado = 'activa'
      AND u.estado = 'activo'
      AND e.estado = 'activo'
  ) THEN
    RAISE EXCEPTION 'No autorizado para esta unidad' USING ERRCODE = '42501';
  END IF;

  -- Impide asociar una solicitud a una ficha de otra persona o unidad.
  IF NOT EXISTS (
    SELECT 1
    FROM public.vecinos AS v
    WHERE v.id = p_integrante_id
      AND v.unidad_id = v_req.unidad_id
      AND v.auth_user_id = v_req.auth_user_id
  ) THEN
    RAISE EXCEPTION 'La identidad verificada no coincide con la solicitud' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.membresias_vecinales (
    auth_user_id, integrante_id, unidad_id, rol, estado,
    solicitada_at, aprobada_at, aprobada_por
  ) VALUES (
    v_req.auth_user_id, p_integrante_id, v_req.unidad_id, 'integrante',
    'activa', v_req.creada_at, pg_catalog.now(), v_actor
  )
  RETURNING id INTO v_membership_id;

  UPDATE public.solicitudes_ingreso_vecinales
  SET estado = 'aprobada',
      revisada_at = pg_catalog.now(),
      revisada_por = v_actor
  WHERE id = v_req.id;

  INSERT INTO public.auditoria_vecinal (
    actor_auth_user_id, unidad_id, integrante_id, accion, resultado
  ) VALUES (
    v_actor, v_req.unidad_id, p_integrante_id, 'membresia_aprobada', 'exito'
  );

  RETURN v_membership_id;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'La cuenta o integrante ya tiene una membresía en esta unidad' USING ERRCODE = '23505';
END;
$$;

CREATE OR REPLACE FUNCTION public.rechazar_ingreso_vecinal(
  p_solicitud_id uuid,
  p_motivo text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_req public.solicitudes_ingreso_vecinales%ROWTYPE;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Sesión requerida' USING ERRCODE = '42501';
  END IF;

  SELECT s.* INTO v_req
  FROM public.solicitudes_ingreso_vecinales AS s
  WHERE s.id = p_solicitud_id
  FOR UPDATE;

  IF NOT FOUND OR v_req.estado <> 'pendiente' THEN
    RAISE EXCEPTION 'Solicitud no disponible' USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.membresias_vecinales AS m
    WHERE m.auth_user_id = v_actor
      AND m.unidad_id = v_req.unidad_id
      AND m.rol = 'titular'
      AND m.estado = 'activa'
  ) THEN
    RAISE EXCEPTION 'No autorizado para esta unidad' USING ERRCODE = '42501';
  END IF;

  UPDATE public.solicitudes_ingreso_vecinales
  SET estado = 'rechazada',
      revisada_at = pg_catalog.now(),
      revisada_por = v_actor,
      motivo_revision = pg_catalog.left(pg_catalog.btrim(COALESCE(p_motivo, '')), 240)
  WHERE id = v_req.id;

  INSERT INTO public.auditoria_vecinal (
    actor_auth_user_id, unidad_id, accion, resultado, motivo
  ) VALUES (
    v_actor, v_req.unidad_id, 'solicitud_ingreso', 'rechazo',
    pg_catalog.left(pg_catalog.btrim(COALESCE(p_motivo, '')), 240)
  );

  RETURN true;
END;
$$;

-- Revocación por titular o auto-baja. No permite eliminar al último titular
-- activo; la transferencia de titularidad requiere un flujo separado.
CREATE OR REPLACE FUNCTION public.revocar_membresia_vecinal(
  p_membresia_id uuid,
  p_motivo text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_member public.membresias_vecinales%ROWTYPE;
  v_is_owner boolean;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Sesión requerida' USING ERRCODE = '42501';
  END IF;

  SELECT m.* INTO v_member
  FROM public.membresias_vecinales AS m
  WHERE m.id = p_membresia_id
  FOR UPDATE;

  IF NOT FOUND OR v_member.estado <> 'activa' THEN
    RAISE EXCEPTION 'Membresía no disponible' USING ERRCODE = '22023';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.membresias_vecinales AS m
    WHERE m.auth_user_id = v_actor
      AND m.unidad_id = v_member.unidad_id
      AND m.rol = 'titular'
      AND m.estado = 'activa'
  ) INTO v_is_owner;

  IF v_member.auth_user_id <> v_actor AND NOT v_is_owner THEN
    RAISE EXCEPTION 'No autorizado para revocar esta membresía' USING ERRCODE = '42501';
  END IF;

  IF v_member.rol = 'titular' AND (
    SELECT pg_catalog.count(*)
    FROM public.membresias_vecinales AS m
    WHERE m.unidad_id = v_member.unidad_id
      AND m.rol = 'titular'
      AND m.estado = 'activa'
  ) <= 1 THEN
    RAISE EXCEPTION 'Debe transferirse la titularidad antes de revocar al último titular' USING ERRCODE = '23514';
  END IF;

  UPDATE public.membresias_vecinales
  SET estado = 'revocada',
      revocada_at = pg_catalog.now(),
      revocada_por = v_actor,
      motivo_revocacion = pg_catalog.left(pg_catalog.btrim(COALESCE(p_motivo, '')), 240)
  WHERE id = v_member.id;

  INSERT INTO public.auditoria_vecinal (
    actor_auth_user_id, unidad_id, integrante_id, accion, resultado, motivo
  ) VALUES (
    v_actor, v_member.unidad_id, v_member.integrante_id,
    'membresia_revocada', 'exito',
    pg_catalog.left(pg_catalog.btrim(COALESCE(p_motivo, '')), 240)
  );

  RETURN true;
END;
$$;

-- Devuelve solo membresías de la sesión; nunca acepta user_id como parámetro.
CREATE OR REPLACE FUNCTION public.mi_contexto_vecinal()
RETURNS TABLE (
  membresia_id uuid,
  unidad_id uuid,
  integrante_id uuid,
  rol text,
  estado text,
  direccion text,
  tipo_unidad text,
  identificador_unidad text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT m.id, m.unidad_id, m.integrante_id, m.rol, m.estado,
         e.direccion, u.tipo, u.identificador
  FROM public.membresias_vecinales AS m
  JOIN public.unidades AS u ON u.id = m.unidad_id
  JOIN public.establecimientos AS e ON e.id = u.establecimiento_id
  WHERE m.auth_user_id = auth.uid()
    AND m.estado = 'activa'
    AND u.estado = 'activo'
    AND e.estado = 'activo';
$$;

REVOKE ALL ON FUNCTION public.aprobar_ingreso_vecinal(uuid, uuid)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rechazar_ingreso_vecinal(uuid, text)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.revocar_membresia_vecinal(uuid, text)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mi_contexto_vecinal()
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.aprobar_ingreso_vecinal(uuid, uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.rechazar_ingreso_vecinal(uuid, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.revocar_membresia_vecinal(uuid, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.mi_contexto_vecinal()
  TO authenticated;

COMMIT;

-- BLOQUEANTES:
-- A. Crear/vincular public.vecinos.auth_user_id solo desde backend confiable.
-- B. Implementar bootstrap verificado del primer titular y transferencia.
-- C. Añadir notificación al solicitante tras aprobación/rechazo.
-- D. Auditar quién puede ver datos declarados de solicitudes.
-- E. Revisar interbloqueos, carreras de último titular y roles múltiples.
-- F. Ejecutar pruebas con usuarios Auth y datos sintéticos en Supabase aislado.
-- G. El rol tutor no concede permisos de titular automáticamente.
