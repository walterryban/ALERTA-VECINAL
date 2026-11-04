-- VIGIARED
-- IDENTIDAD, MEMBRESIAS E INVITACIONES VECINALES v0.2
-- BORRADOR DE MIGRACION — NO EJECUTAR NI DESPLEGAR.
--
-- Dependencia: docs/migracion-red-comunitaria-v0.1-borrador.sql
-- Requiere un proyecto Supabase AISLADO, backup, revisión independiente
-- y autorización expresa antes de cualquier ejecución.
--
-- Corrección central: auth.users -> perfiles_vecinales -> membresias_vecinales.
-- Una persona tiene un perfil y puede pertenecer a muchas unidades.
-- public.vecinos queda fuera de la autorización moderna y no se migra
-- ni se empareja automáticamente con identidades existentes.
--
-- Las tablas manzanas/alertas y sus datos ficticios no se modifican.
-- No se crean usuarios Auth ni se envían invitaciones reales.
--
-- PRECONDICIONES:
-- 1. La migración de red comunitaria creó establecimientos y unidades.
-- 2. Los borradores de identidad/invitaciones/aprobación v0.1 NO fueron ejecutados.
-- 3. El rol PostgreSQL service_role existe (Supabase).
-- 4. El primer titular será inicializado solo por backend confiable tras
--    verificación externa documentada. Nunca por QR, PIN, domicilio o cliente.

BEGIN;

DO $preflight$
BEGIN
  IF to_regclass('public.perfiles_vecinales') IS NOT NULL
     OR to_regclass('public.membresias_vecinales') IS NOT NULL
     OR to_regclass('public.invitaciones_vecinales') IS NOT NULL
     OR to_regclass('public.solicitudes_ingreso_vecinales') IS NOT NULL
     OR to_regclass('public.auditoria_vecinal') IS NOT NULL THEN
    RAISE EXCEPTION
      'Preflight VIGIARED v0.2: ya existen tablas de identidad/membresía. Detener y reconciliar esquema; no sobrescribir.';
  END IF;

  IF to_regclass('public.unidades') IS NULL
     OR to_regclass('public.establecimientos') IS NULL THEN
    RAISE EXCEPTION
      'Preflight VIGIARED v0.2: faltan establecimientos/unidades. Aplicar primero la revisión de red comunitaria en un entorno aislado.';
  END IF;
END
$preflight$;

CREATE TABLE public.perfiles_vecinales (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  auth_user_id uuid NOT NULL UNIQUE
    REFERENCES auth.users(id) ON DELETE RESTRICT,
  nombre_mostrado text,
  telefono_e164 text,
  telefono_verificado_at timestamptz,
  estado text NOT NULL DEFAULT 'activo'
    CHECK (estado IN ('activo', 'suspendido', 'bloqueado')),
  creado_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  actualizado_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  CONSTRAINT perfiles_nombre_ck CHECK (
    nombre_mostrado IS NULL OR
    pg_catalog.length(pg_catalog.btrim(nombre_mostrado)) BETWEEN 2 AND 120
  ),
  CONSTRAINT perfiles_telefono_ck CHECK (
    telefono_e164 IS NULL OR
    pg_catalog.length(telefono_e164) BETWEEN 8 AND 20
  )
);

CREATE TABLE public.membresias_vecinales (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  perfil_id uuid NOT NULL
    REFERENCES public.perfiles_vecinales(id) ON DELETE RESTRICT,
  unidad_id uuid NOT NULL
    REFERENCES public.unidades(id) ON DELETE RESTRICT,
  rol text NOT NULL DEFAULT 'integrante'
    CHECK (rol IN ('titular', 'integrante', 'tutor')),
  estado text NOT NULL DEFAULT 'pendiente'
    CHECK (estado IN ('activa', 'suspendida', 'revocada')),
  creada_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  aprobada_at timestamptz,
  aprobada_por uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  revocada_at timestamptz,
  revocada_por uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  motivo_revocacion text,
  CONSTRAINT membresia_perfil_unidad_uk UNIQUE (perfil_id, unidad_id),
  CONSTRAINT membresia_aprobacion_ck CHECK (
    (estado <> 'activa') OR (aprobada_at IS NOT NULL AND aprobada_por IS NOT NULL)
  ),
  CONSTRAINT membresia_revocacion_ck CHECK (
    (estado <> 'revocada') OR (revocada_at IS NOT NULL AND revocada_por IS NOT NULL)
  )
);

CREATE INDEX membresias_unidad_estado_idx
  ON public.membresias_vecinales (unidad_id, estado);
CREATE INDEX membresias_perfil_estado_idx
  ON public.membresias_vecinales (perfil_id, estado);

CREATE TABLE public.invitaciones_vecinales (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  unidad_id uuid NOT NULL
    REFERENCES public.unidades(id) ON DELETE RESTRICT,
  token_hash bytea NOT NULL UNIQUE,
  emitida_por uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  emitida_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  expira_at timestamptz NOT NULL,
  usada_at timestamptz,
  revocada_at timestamptz,
  revocada_por uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  CONSTRAINT invitacion_expiracion_ck CHECK (expira_at > emitida_at)
);

CREATE INDEX invitaciones_unidad_expira_idx
  ON public.invitaciones_vecinales (unidad_id, expira_at);

CREATE TABLE public.solicitudes_ingreso_vecinales (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  perfil_id uuid NOT NULL
    REFERENCES public.perfiles_vecinales(id) ON DELETE RESTRICT,
  unidad_id uuid NOT NULL
    REFERENCES public.unidades(id) ON DELETE RESTRICT,
  estado text NOT NULL DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente', 'aprobada', 'rechazada', 'cancelada')),
  creada_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  revisada_at timestamptz,
  revisada_por uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  motivo_revision text
);

CREATE UNIQUE INDEX solicitudes_ingreso_pendiente_uk
  ON public.solicitudes_ingreso_vecinales (perfil_id, unidad_id)
  WHERE estado = 'pendiente';
CREATE INDEX solicitudes_ingreso_unidad_estado_idx
  ON public.solicitudes_ingreso_vecinales (unidad_id, estado, creada_at DESC);

CREATE TABLE public.auditoria_vecinal (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  actor_auth_user_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  perfil_id uuid REFERENCES public.perfiles_vecinales(id) ON DELETE RESTRICT,
  unidad_id uuid REFERENCES public.unidades(id) ON DELETE RESTRICT,
  accion text NOT NULL CHECK (accion IN (
    'perfil_provisionado', 'titular_inicializado', 'invitacion_emitida',
    'invitacion_revocada', 'solicitud_ingreso', 'membresia_aprobada',
    'solicitud_rechazada', 'membresia_revocada'
  )),
  resultado text NOT NULL CHECK (resultado IN ('exito', 'rechazo')),
  referencia_verificacion text,
  motivo text,
  creado_at timestamptz NOT NULL DEFAULT pg_catalog.now()
);

CREATE INDEX auditoria_vecinal_unidad_fecha_idx
  ON public.auditoria_vecinal (unidad_id, creado_at DESC);

-- Sin acceso directo desde navegador. Todas las operaciones pasan por RPC.
ALTER TABLE public.perfiles_vecinales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.membresias_vecinales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invitaciones_vecinales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.solicitudes_ingreso_vecinales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.auditoria_vecinal ENABLE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES ON TABLE
  public.perfiles_vecinales,
  public.membresias_vecinales,
  public.invitaciones_vecinales,
  public.solicitudes_ingreso_vecinales,
  public.auditoria_vecinal
FROM PUBLIC, anon, authenticated;

REVOKE ALL ON SEQUENCE public.auditoria_vecinal_id_seq
FROM PUBLIC, anon, authenticated;

-- Solo backend confiable (service_role) puede provisionar perfil.
-- auth.users debe existir y tener email o teléfono confirmado.
CREATE FUNCTION public.provisionar_perfil_vecinal(
  p_auth_user_id uuid,
  p_nombre_mostrado text DEFAULT NULL,
  p_telefono_e164 text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_profile_id uuid;
  v_confirmed boolean;
BEGIN
  IF p_auth_user_id IS NULL THEN
    RAISE EXCEPTION 'Cuenta requerida' USING ERRCODE = '22023';
  END IF;

  SELECT (u.email_confirmed_at IS NOT NULL OR u.phone_confirmed_at IS NOT NULL)
  INTO v_confirmed
  FROM auth.users AS u
  WHERE u.id = p_auth_user_id;

  IF NOT COALESCE(v_confirmed, false) THEN
    RAISE EXCEPTION 'La cuenta debe estar verificada' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.perfiles_vecinales (
    auth_user_id, nombre_mostrado, telefono_e164
  ) VALUES (
    p_auth_user_id,
    NULLIF(pg_catalog.btrim(COALESCE(p_nombre_mostrado, '')), ''),
    NULLIF(pg_catalog.btrim(COALESCE(p_telefono_e164, '')), '')
  )
  ON CONFLICT (auth_user_id) DO UPDATE
    SET nombre_mostrado = COALESCE(
          EXCLUDED.nombre_mostrado, public.perfiles_vecinales.nombre_mostrado
        ),
        telefono_e164 = COALESCE(
          EXCLUDED.telefono_e164, public.perfiles_vecinales.telefono_e164
        ),
        actualizado_at = pg_catalog.now()
  RETURNING id INTO v_profile_id;

  INSERT INTO public.auditoria_vecinal (
    actor_auth_user_id, perfil_id, accion, resultado
  ) VALUES (
    p_auth_user_id, v_profile_id, 'perfil_provisionado', 'exito'
  );

  RETURN v_profile_id;
END;
$$;

-- Bootstrap exclusivo de backend confiable después de verificación fuera de banda.
-- La referencia debe apuntar a un expediente/proceso auditable; no es prueba
-- por sí misma. La validación sustantiva ocurre en el sistema operador.
CREATE FUNCTION public.inicializar_titular_vecinal(
  p_auth_user_id uuid,
  p_unidad_id uuid,
  p_referencia_verificacion text
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_profile_id uuid;
  v_membership_id uuid;
  v_confirmed boolean;
BEGIN
  IF p_auth_user_id IS NULL OR p_unidad_id IS NULL
     OR p_referencia_verificacion IS NULL
     OR pg_catalog.length(pg_catalog.btrim(p_referencia_verificacion)) NOT BETWEEN 6 AND 160 THEN
    RAISE EXCEPTION 'Datos de bootstrap inválidos' USING ERRCODE = '22023';
  END IF;

  SELECT (u.email_confirmed_at IS NOT NULL OR u.phone_confirmed_at IS NOT NULL)
  INTO v_confirmed
  FROM auth.users AS u
  WHERE u.id = p_auth_user_id;

  IF NOT COALESCE(v_confirmed, false) THEN
    RAISE EXCEPTION 'La cuenta debe estar verificada' USING ERRCODE = '42501';
  END IF;

  PERFORM 1
  FROM public.unidades AS un
  JOIN public.establecimientos AS es ON es.id = un.establecimiento_id
  WHERE un.id = p_unidad_id
    AND un.estado = 'activo'
    AND es.estado = 'activo'
  FOR UPDATE OF un;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unidad no disponible' USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.membresias_vecinales AS m
    WHERE m.unidad_id = p_unidad_id
      AND m.rol = 'titular'
      AND m.estado = 'activa'
  ) THEN
    RAISE EXCEPTION 'La unidad ya tiene titular activo' USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.perfiles_vecinales (auth_user_id)
  VALUES (p_auth_user_id)
  ON CONFLICT (auth_user_id) DO UPDATE
    SET actualizado_at = pg_catalog.now()
  RETURNING id INTO v_profile_id;

  INSERT INTO public.membresias_vecinales (
    perfil_id, unidad_id, rol, estado, aprobada_at, aprobada_por
  ) VALUES (
    v_profile_id, p_unidad_id, 'titular', 'activa',
    pg_catalog.now(), p_auth_user_id
  )
  ON CONFLICT (perfil_id, unidad_id) DO UPDATE
    SET rol = 'titular',
        estado = 'activa',
        aprobada_at = pg_catalog.now(),
        aprobada_por = p_auth_user_id,
        revocada_at = NULL,
        revocada_por = NULL,
        motivo_revocacion = NULL
  RETURNING id INTO v_membership_id;

  INSERT INTO public.auditoria_vecinal (
    actor_auth_user_id, perfil_id, unidad_id, accion, resultado,
    referencia_verificacion
  ) VALUES (
    p_auth_user_id, v_profile_id, p_unidad_id, 'titular_inicializado',
    'exito', pg_catalog.btrim(p_referencia_verificacion)
  );

  RETURN v_membership_id;
END;
$$;

CREATE FUNCTION public.emitir_invitacion_vecinal(
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
  v_profile_id uuid;
  v_token text;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Sesión requerida' USING ERRCODE = '42501';
  END IF;
  IF p_unidad_id IS NULL OR p_vigencia_horas NOT BETWEEN 1 AND 72 THEN
    RAISE EXCEPTION 'Solicitud inválida' USING ERRCODE = '22023';
  END IF;

  SELECT p.id INTO v_profile_id
  FROM public.perfiles_vecinales AS p
  WHERE p.auth_user_id = v_actor AND p.estado = 'activo';

  IF v_profile_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.membresias_vecinales AS m
    JOIN public.unidades AS un ON un.id = m.unidad_id
    JOIN public.establecimientos AS es ON es.id = un.establecimiento_id
    WHERE m.perfil_id = v_profile_id AND m.unidad_id = p_unidad_id
      AND m.rol = 'titular' AND m.estado = 'activa'
      AND un.estado = 'activo' AND es.estado = 'activo'
  ) THEN
    RAISE EXCEPTION 'No autorizado para esta unidad' USING ERRCODE = '42501';
  END IF;

  IF (
    SELECT pg_catalog.count(*)
    FROM public.auditoria_vecinal AS a
    WHERE a.actor_auth_user_id = v_actor
      AND a.accion = 'invitacion_emitida'
      AND a.resultado = 'exito'
      AND a.creado_at > pg_catalog.now() - interval '1 hour'
  ) >= 10 THEN
    RAISE EXCEPTION 'Límite temporal de invitaciones alcanzado' USING ERRCODE = '54000';
  END IF;

  v_token := pg_catalog.translate(
    pg_catalog.rtrim(
      pg_catalog.replace(
        pg_catalog.encode(extensions.gen_random_bytes(32), 'base64'),
        E'\\n', ''
      ), '='
    ), '+/', '-_'
  );

  INSERT INTO public.invitaciones_vecinales (
    unidad_id, token_hash, emitida_por, expira_at
  ) VALUES (
    p_unidad_id,
    extensions.digest(pg_catalog.convert_to(v_token, 'UTF8'), 'sha256'),
    v_actor,
    pg_catalog.now() + pg_catalog.make_interval(hours => p_vigencia_horas)
  );

  INSERT INTO public.auditoria_vecinal (
    actor_auth_user_id, perfil_id, unidad_id, accion, resultado
  ) VALUES (
    v_actor, v_profile_id, p_unidad_id, 'invitacion_emitida', 'exito'
  );

  RETURN v_token;
END;
$$;

-- El token es de un solo uso. El canje crea solicitud pendiente, nunca
-- membresía activa. El perfil debe haber sido provisionado por backend.
CREATE FUNCTION public.solicitar_ingreso_vecinal(p_token text)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_profile_id uuid;
  v_inv public.invitaciones_vecinales%ROWTYPE;
  v_request_id uuid;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Sesión requerida' USING ERRCODE = '42501';
  END IF;
  IF p_token IS NULL OR pg_catalog.length(p_token) NOT BETWEEN 40 AND 100 THEN
    RAISE EXCEPTION 'Invitación inválida o vencida' USING ERRCODE = '22023';
  END IF;

  SELECT p.id INTO v_profile_id
  FROM public.perfiles_vecinales AS p
  WHERE p.auth_user_id = v_actor AND p.estado = 'activo';

  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'Perfil no habilitado' USING ERRCODE = '42501';
  END IF;

  SELECT i.* INTO v_inv
  FROM public.invitaciones_vecinales AS i
  WHERE i.token_hash = extensions.digest(
    pg_catalog.convert_to(p_token, 'UTF8'), 'sha256'
  )
  FOR UPDATE;

  IF NOT FOUND OR v_inv.usada_at IS NOT NULL
     OR v_inv.revocada_at IS NOT NULL OR v_inv.expira_at <= pg_catalog.now() THEN
    RAISE EXCEPTION 'Invitación inválida o vencida' USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.membresias_vecinales AS m
    WHERE m.perfil_id = v_profile_id
      AND m.unidad_id = v_inv.unidad_id
      AND m.estado = 'activa'
  ) THEN
    RAISE EXCEPTION 'La cuenta ya pertenece a esta unidad' USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.solicitudes_ingreso_vecinales (perfil_id, unidad_id)
  VALUES (v_profile_id, v_inv.unidad_id)
  RETURNING id INTO v_request_id;

  UPDATE public.invitaciones_vecinales
  SET usada_at = pg_catalog.now()
  WHERE id = v_inv.id;

  INSERT INTO public.auditoria_vecinal (
    actor_auth_user_id, perfil_id, unidad_id, accion, resultado
  ) VALUES (
    v_actor, v_profile_id, v_inv.unidad_id, 'solicitud_ingreso', 'exito'
  );

  RETURN v_request_id;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'Ya existe una solicitud pendiente o una membresía para esta unidad'
      USING ERRCODE = '23505';
END;
$$;

CREATE FUNCTION public.aprobar_ingreso_vecinal(p_solicitud_id uuid)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_profile_id uuid;
  v_unit_id uuid;
  v_membership_id uuid;
BEGIN
  IF v_actor IS NULL OR p_solicitud_id IS NULL THEN
    RAISE EXCEPTION 'Sesión o solicitud inválida' USING ERRCODE = '42501';
  END IF;

  SELECT s.perfil_id, s.unidad_id
  INTO v_profile_id, v_unit_id
  FROM public.solicitudes_ingreso_vecinales AS s
  WHERE s.id = p_solicitud_id AND s.estado = 'pendiente'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Solicitud no disponible' USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.membresias_vecinales AS m
    JOIN public.perfiles_vecinales AS p ON p.id = m.perfil_id
    WHERE p.auth_user_id = v_actor AND p.estado = 'activo'
      AND m.unidad_id = v_unit_id AND m.rol = 'titular' AND m.estado = 'activa'
  ) THEN
    RAISE EXCEPTION 'No autorizado para esta unidad' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.perfiles_vecinales AS p
    JOIN auth.users AS u ON u.id = p.auth_user_id
    WHERE p.id = v_profile_id AND p.estado = 'activo'
      AND (u.email_confirmed_at IS NOT NULL OR u.phone_confirmed_at IS NOT NULL)
  ) THEN
    RAISE EXCEPTION 'La cuenta solicitante no está verificada o habilitada'
      USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.membresias_vecinales (
    perfil_id, unidad_id, rol, estado, aprobada_at, aprobada_por
  ) VALUES (
    v_profile_id, v_unit_id, 'integrante', 'activa', pg_catalog.now(), v_actor
  )
  ON CONFLICT (perfil_id, unidad_id) DO UPDATE
    SET rol = 'integrante', estado = 'activa',
        aprobada_at = pg_catalog.now(), aprobada_por = v_actor,
        revocada_at = NULL, revocada_por = NULL, motivo_revocacion = NULL
  RETURNING id INTO v_membership_id;

  UPDATE public.solicitudes_ingreso_vecinales
  SET estado = 'aprobada', revisada_at = pg_catalog.now(), revisada_por = v_actor
  WHERE id = p_solicitud_id;

  INSERT INTO public.auditoria_vecinal (
    actor_auth_user_id, perfil_id, unidad_id, accion, resultado
  ) VALUES (
    v_actor, v_profile_id, v_unit_id, 'membresia_aprobada', 'exito'
  );

  RETURN v_membership_id;
END;
$$;

CREATE FUNCTION public.rechazar_ingreso_vecinal(
  p_solicitud_id uuid, p_motivo text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_profile_id uuid;
  v_unit_id uuid;
BEGIN
  SELECT s.perfil_id, s.unidad_id
  INTO v_profile_id, v_unit_id
  FROM public.solicitudes_ingreso_vecinales AS s
  WHERE s.id = p_solicitud_id AND s.estado = 'pendiente'
  FOR UPDATE;

  IF v_actor IS NULL OR NOT FOUND THEN
    RAISE EXCEPTION 'Solicitud no disponible' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.membresias_vecinales AS m
    JOIN public.perfiles_vecinales AS p ON p.id = m.perfil_id
    WHERE p.auth_user_id = v_actor AND m.unidad_id = v_unit_id
      AND m.rol = 'titular' AND m.estado = 'activa'
  ) THEN
    RAISE EXCEPTION 'No autorizado para esta unidad' USING ERRCODE = '42501';
  END IF;

  UPDATE public.solicitudes_ingreso_vecinales
  SET estado = 'rechazada', revisada_at = pg_catalog.now(),
      revisada_por = v_actor,
      motivo_revision = pg_catalog.left(pg_catalog.btrim(COALESCE(p_motivo, '')), 240)
  WHERE id = p_solicitud_id;

  INSERT INTO public.auditoria_vecinal (
    actor_auth_user_id, perfil_id, unidad_id, accion, resultado, motivo
  ) VALUES (
    v_actor, v_profile_id, v_unit_id, 'solicitud_rechazada', 'exito',
    pg_catalog.left(pg_catalog.btrim(COALESCE(p_motivo, '')), 240)
  );

  RETURN true;
END;
$$;

CREATE FUNCTION public.revocar_membresia_vecinal(
  p_membresia_id uuid, p_motivo text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_unit_id uuid;
  v_profile_id uuid;
  v_role text;
  v_target_auth uuid;
  v_actor_profile uuid;
  v_is_titular boolean;
BEGIN
  IF v_actor IS NULL OR p_membresia_id IS NULL THEN
    RAISE EXCEPTION 'Sesión o membresía inválida' USING ERRCODE = '42501';
  END IF;

  SELECT m.unidad_id INTO v_unit_id
  FROM public.membresias_vecinales AS m
  WHERE m.id = p_membresia_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Membresía no disponible' USING ERRCODE = '22023';
  END IF;

  PERFORM 1 FROM public.unidades AS u
  WHERE u.id = v_unit_id
  FOR UPDATE;

  SELECT m.perfil_id, m.rol, p.auth_user_id
  INTO v_profile_id, v_role, v_target_auth
  FROM public.membresias_vecinales AS m
  JOIN public.perfiles_vecinales AS p ON p.id = m.perfil_id
  WHERE m.id = p_membresia_id AND m.estado = 'activa'
  FOR UPDATE OF m;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Membresía no disponible' USING ERRCODE = '22023';
  END IF;

  SELECT p.id INTO v_actor_profile
  FROM public.perfiles_vecinales AS p
  WHERE p.auth_user_id = v_actor AND p.estado = 'activo';

  SELECT EXISTS (
    SELECT 1 FROM public.membresias_vecinales AS m
    WHERE m.perfil_id = v_actor_profile AND m.unidad_id = v_unit_id
      AND m.rol = 'titular' AND m.estado = 'activa'
  ) INTO v_is_titular;

  IF v_target_auth <> v_actor AND NOT v_is_titular THEN
    RAISE EXCEPTION 'No autorizado para revocar esta membresía' USING ERRCODE = '42501';
  END IF;

  IF v_role = 'titular' AND (
    SELECT pg_catalog.count(*) FROM public.membresias_vecinales AS m
    WHERE m.unidad_id = v_unit_id AND m.rol = 'titular' AND m.estado = 'activa'
  ) <= 1 THEN
    RAISE EXCEPTION 'Debe transferirse la titularidad antes de revocar al último titular'
      USING ERRCODE = '23514';
  END IF;

  UPDATE public.membresias_vecinales
  SET estado = 'revocada', revocada_at = pg_catalog.now(),
      revocada_por = v_actor,
      motivo_revocacion = pg_catalog.left(pg_catalog.btrim(COALESCE(p_motivo, '')), 240)
  WHERE id = p_membresia_id;

  INSERT INTO public.auditoria_vecinal (
    actor_auth_user_id, perfil_id, unidad_id, accion, resultado, motivo
  ) VALUES (
    v_actor, v_profile_id, v_unit_id, 'membresia_revocada', 'exito',
    pg_catalog.left(pg_catalog.btrim(COALESCE(p_motivo, '')), 240)
  );

  RETURN true;
END;
$$;

CREATE FUNCTION public.mi_contexto_vecinal()
RETURNS TABLE (
  perfil_id uuid,
  membresia_id uuid,
  unidad_id uuid,
  rol text,
  direccion text,
  tipo_unidad text,
  identificador_unidad text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT p.id, m.id, m.unidad_id, m.rol,
         es.direccion, un.tipo, un.identificador
  FROM public.perfiles_vecinales AS p
  JOIN public.membresias_vecinales AS m ON m.perfil_id = p.id
  JOIN public.unidades AS un ON un.id = m.unidad_id
  JOIN public.establecimientos AS es ON es.id = un.establecimiento_id
  WHERE p.auth_user_id = auth.uid()
    AND p.estado = 'activo' AND m.estado = 'activa'
    AND un.estado = 'activo' AND es.estado = 'activo';
$$;

-- RPCs de usuario: solo authenticated. El bootstrap/provisionamiento es
-- exclusivamente service_role. Ninguna tabla concede acceso directo.
REVOKE ALL ON FUNCTION public.provisionar_perfil_vecinal(uuid, text, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.inicializar_titular_vecinal(uuid, uuid, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.emitir_invitacion_vecinal(uuid, integer)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.solicitar_ingreso_vecinal(text)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.aprobar_ingreso_vecinal(uuid)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rechazar_ingreso_vecinal(uuid, text)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.revocar_membresia_vecinal(uuid, text)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mi_contexto_vecinal()
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.provisionar_perfil_vecinal(uuid, text, text)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.inicializar_titular_vecinal(uuid, uuid, text)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.emitir_invitacion_vecinal(uuid, integer)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.solicitar_ingreso_vecinal(text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.aprobar_ingreso_vecinal(uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.rechazar_ingreso_vecinal(uuid, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.revocar_membresia_vecinal(uuid, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.mi_contexto_vecinal()
  TO authenticated;

COMMIT;

-- PRUEBAS OBLIGATORIAS EN PROYECTO AISLADO ANTES DE CONSIDERAR EJECUCION:
-- * Una cuenta tiene un perfil único y membresías en varias unidades.
-- * Revocar en unidad A no afecta unidad B ni la cuenta Auth.
-- * No se puede crear perfil por cliente ni asignarse como primer titular.
-- * Invitación: hash únicamente, un solo canje, vencimiento y revocación.
-- * Canje genera solicitud pendiente; nunca activa membresía.
-- * Solo titular de la misma unidad puede aprobar/rechazar/emitir invitación.
-- * Solo titular o propio integrante puede revocar; nunca el último titular.
-- * Pruebas concurrentes de canje, aprobación y revocación.
-- * Usuario sin membresía no obtiene contexto ni datos de otras unidades.
-- * Verificar el rol service_role, privilegios efectivos y SECURITY DEFINER.
-- * Revisión de auditoría, rate limits, recuperación de titularidad y menores.
--
-- LIMITACIONES CONOCIDAS / SIGUIENTES ITERACIONES:
-- * La verificación documental/telefónica y el alta del primer titular son
--   procesos operativos externos; este SQL no acredita identidad por sí solo.
-- * Falta flujo de transferencia de titularidad y cancelación de solicitud.
-- * Falta una vista autenticada y limitada de solicitudes pendientes para el
--   titular; no se habilita SELECT directo en estas tablas.
-- * No integra todavía alertas, notificaciones push ni terminal.html.
