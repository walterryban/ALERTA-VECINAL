-- VIGIARED
-- IDENTIDAD VECINAL v0.1 — BORRADOR ADITIVO / NO EJECUTAR
-- Dependencia: docs/migracion-red-comunitaria-v0.1-borrador.sql
-- Objetivo: cuentas Supabase Auth individuales, membresías por unidad,
-- invitaciones de un solo uso y auditoría mínima.
--
-- Este archivo NO crea usuarios Auth, no emite invitaciones y no modifica
-- alertas/manzanas ni datos ficticios existentes.
-- Requiere ensayo en un proyecto Supabase aislado y revisión de seguridad.

BEGIN;

-- Permite garantizar que la persona y la unidad de la membresía coincidan.
-- Las personas históricas con unidad_id NULL permanecen intactas.
CREATE UNIQUE INDEX IF NOT EXISTS vecinos_id_unidad_uk
  ON public.vecinos (id, unidad_id);

CREATE TABLE IF NOT EXISTS public.membresias_vecinales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  integrante_id uuid NOT NULL,
  unidad_id uuid NOT NULL,
  rol text NOT NULL DEFAULT 'integrante'
    CHECK (rol IN ('titular', 'integrante', 'tutor')),
  estado text NOT NULL DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente', 'activa', 'suspendida', 'revocada')),
  solicitada_at timestamptz NOT NULL DEFAULT now(),
  aprobada_at timestamptz,
  aprobada_por uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  revocada_at timestamptz,
  revocada_por uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  motivo_revocacion text,
  CONSTRAINT membresias_vecinales_persona_unidad_fk
    FOREIGN KEY (integrante_id, unidad_id)
    REFERENCES public.vecinos (id, unidad_id)
    ON DELETE RESTRICT,
  CONSTRAINT membresias_vecinales_usuario_unidad_uk
    UNIQUE (auth_user_id, unidad_id),
  CONSTRAINT membresias_vecinales_integrante_unidad_uk
    UNIQUE (integrante_id, unidad_id),
  CONSTRAINT membresias_vecinales_aprobacion_ck
    CHECK (
      (estado <> 'activa' OR (aprobada_at IS NOT NULL AND aprobada_por IS NOT NULL))
    ),
  CONSTRAINT membresias_vecinales_revocacion_ck
    CHECK (
      (estado <> 'revocada' OR (revocada_at IS NOT NULL AND revocada_por IS NOT NULL))
    )
);

CREATE INDEX IF NOT EXISTS membresias_vecinales_auth_user_idx
  ON public.membresias_vecinales (auth_user_id, estado);
CREATE INDEX IF NOT EXISTS membresias_vecinales_unidad_idx
  ON public.membresias_vecinales (unidad_id, estado);

-- Invitaciones: solo se conserva el hash; el token en claro se entrega
-- una sola vez. La RPC de canje deberá bloquear la fila FOR UPDATE,
-- comprobar vencimiento/uso y crear la solicitud sin activar por sí sola.
CREATE TABLE IF NOT EXISTS public.invitaciones_vecinales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  unidad_id uuid NOT NULL REFERENCES public.unidades(id) ON DELETE RESTRICT,
  token_hash bytea NOT NULL UNIQUE,
  emitida_por uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  emitida_at timestamptz NOT NULL DEFAULT now(),
  expira_at timestamptz NOT NULL,
  max_usos integer NOT NULL DEFAULT 1 CHECK (max_usos = 1),
  usos integer NOT NULL DEFAULT 0 CHECK (usos BETWEEN 0 AND 1),
  usada_at timestamptz,
  revocada_at timestamptz,
  revocada_por uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  CHECK (expira_at > emitida_at),
  CHECK (usada_at IS NULL OR usos = 1)
);

CREATE INDEX IF NOT EXISTS invitaciones_vecinales_unidad_idx
  ON public.invitaciones_vecinales (unidad_id, expira_at);

-- Auditoría de acciones sensibles. No almacenar tokens, PIN, fichas médicas
-- ni contenido completo de alertas en este registro.
CREATE TABLE IF NOT EXISTS public.auditoria_vecinal (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  actor_auth_user_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  unidad_id uuid REFERENCES public.unidades(id) ON DELETE RESTRICT,
  integrante_id uuid REFERENCES public.vecinos(id) ON DELETE RESTRICT,
  accion text NOT NULL CHECK (accion IN (
    'invitacion_emitida',
    'invitacion_revocada',
    'solicitud_ingreso',
    'membresia_aprobada',
    'membresia_suspendida',
    'membresia_reactivada',
    'membresia_revocada'
  )),
  resultado text NOT NULL CHECK (resultado IN ('exito', 'rechazo')),
  motivo text,
  creado_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS auditoria_vecinal_unidad_fecha_idx
  ON public.auditoria_vecinal (unidad_id, creado_at DESC);

ALTER TABLE public.membresias_vecinales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invitaciones_vecinales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.auditoria_vecinal ENABLE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES ON TABLE
  public.membresias_vecinales,
  public.invitaciones_vecinales,
  public.auditoria_vecinal
FROM PUBLIC, anon, authenticated;

REVOKE ALL ON SEQUENCE public.auditoria_vecinal_id_seq
FROM PUBLIC, anon, authenticated;

COMMIT;

-- IMPORTANTE: no hay políticas de acceso directo intencionalmente.
-- Las operaciones se expondrán únicamente mediante RPC SECURITY DEFINER
-- con search_path vacío, validación explícita de auth.uid(), autorización
-- por unidad y permisos EXECUTE mínimos.
--
-- RPC pendientes (contrato en docs/identidad-y-rpc-vecinales-v0.1.md):
-- 1. emitir_invitacion_vecinal(unidad_id, ttl): titular autorizado.
-- 2. solicitar_ingreso_vecinal(token, datos mínimos): usuario Auth.
-- 3. aprobar_membresia_vecinal(solicitud_id): titular/administrador autorizado.
-- 4. revocar_membresia_vecinal(membresia_id): titular/administrador autorizado.
-- 5. mi_contexto_vecinal(): devuelve solo unidades/membresías propias.
--
-- Antes de crear estas RPC: definir quién puede ser titular inicial,
-- flujo de recuperación de titularidad, tutela de menores y rate limiting.
