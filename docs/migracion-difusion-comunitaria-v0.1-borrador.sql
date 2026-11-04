-- VIGIARED — MODELO DE DIFUSION COMUNITARIA v0.1
-- BORRADOR ADITIVO / NO EJECUTAR NI DESPLEGAR.
-- Diseñado para que una alerta operativa del COM y un aviso comunitario
-- sean canales distintos con distintos niveles de datos.
--
-- NO inserta ni modifica alertas existentes. No asigna las alertas/manzanas
-- ficticias a domicilios reales. La asociación manzana_id queda NULL hasta
-- que una RPC confiable cree una alerta nueva con identidad verificada.

BEGIN;

ALTER TABLE public.alertas
  ADD COLUMN IF NOT EXISTS manzana_id bigint
  REFERENCES public.manzanas(id) ON DELETE RESTRICT;

-- Evento de difusión con información mínima. La alerta original conserva
-- sus datos operativos privados; esta tabla no copia domicilio, nombre,
-- teléfono, ficha médica, coordenadas ni texto libre.
CREATE TABLE IF NOT EXISTS public.difusiones_comunitarias (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  alerta_id uuid NOT NULL UNIQUE
    REFERENCES public.alertas(id) ON DELETE RESTRICT,
  manzana_id bigint NOT NULL
    REFERENCES public.manzanas(id) ON DELETE RESTRICT,
  tipo_alerta text NOT NULL CHECK (tipo_alerta IN (
    'panico', 'robo', 'emergencia', 'actividad_sospechosa', 'otro'
  )),
  estado text NOT NULL DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente', 'procesando', 'completada', 'fallida', 'cancelada')),
  creada_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  procesada_at timestamptz,
  intentos integer NOT NULL DEFAULT 0 CHECK (intentos >= 0),
  ultimo_error_codigo text
);

CREATE INDEX IF NOT EXISTS difusiones_comunitarias_manzana_fecha_idx
  ON public.difusiones_comunitarias (manzana_id, creada_at DESC);

-- Cola de entrega. Un destinatario por membresía activa al momento de
-- crear la difusión. No guarda tokens push; estos viven en un registro
-- separado y revocable por dispositivo.
CREATE TABLE IF NOT EXISTS public.entregas_notificacion_vecinal (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  difusion_id uuid NOT NULL
    REFERENCES public.difusiones_comunitarias(id) ON DELETE RESTRICT,
  membresia_id uuid NOT NULL
    REFERENCES public.membresias_vecinales(id) ON DELETE RESTRICT,
  estado text NOT NULL DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente', 'enviada', 'entregada', 'fallida', 'cancelada')),
  creada_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  intentos integer NOT NULL DEFAULT 0 CHECK (intentos >= 0),
  proximo_intento_at timestamptz,
  enviada_at timestamptz,
  entregada_at timestamptz,
  error_codigo text,
  CONSTRAINT entregas_notificacion_difusion_membresia_uk
    UNIQUE (difusion_id, membresia_id)
);

CREATE INDEX IF NOT EXISTS entregas_notificacion_pendientes_idx
  ON public.entregas_notificacion_vecinal (estado, proximo_intento_at)
  WHERE estado IN ('pendiente', 'fallida');

-- Registro de tokens por dispositivo, cifrados en backend. Nunca accesibles
-- directamente desde anon/authenticated ni retornados por una RPC pública.
CREATE TABLE IF NOT EXISTS public.dispositivos_vecinales (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  plataforma text NOT NULL CHECK (plataforma IN ('web_push', 'android', 'ios')),
  token_cifrado bytea NOT NULL,
  estado text NOT NULL DEFAULT 'activo'
    CHECK (estado IN ('activo', 'revocado', 'invalido')),
  creado_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  ultimo_uso_at timestamptz,
  revocado_at timestamptz
);

CREATE INDEX IF NOT EXISTS dispositivos_vecinales_usuario_estado_idx
  ON public.dispositivos_vecinales (auth_user_id, estado);

ALTER TABLE public.difusiones_comunitarias ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.entregas_notificacion_vecinal ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dispositivos_vecinales ENABLE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES ON TABLE
  public.difusiones_comunitarias,
  public.entregas_notificacion_vecinal,
  public.dispositivos_vecinales
FROM PUBLIC, anon, authenticated;

REVOKE ALL ON SEQUENCE public.entregas_notificacion_vecinal_id_seq
FROM PUBLIC, anon, authenticated;

COMMIT;

-- DISEÑO DE ENTREGA (NO IMPLEMENTADO):
-- 1. RPC segura crea alerta y difusión en una única transacción.
-- 2. El servidor obtiene manzana_id/unidad_id desde membresía activa;
--    no acepta un destino arbitrario del navegador.
-- 3. La difusión crea entregas para integrantes activos de unidades
--    participantes de esa manzana, excluyendo al emisor si se decide.
-- 4. Worker/Edge Function toma la cola con bloqueo SKIP LOCKED y reintentos.
-- 5. Push contiene solo tipo de alerta, hora aproximada y deep-link autenticado.
-- 6. Al abrir, la app consulta el detalle permitido tras verificar sesión.
-- 7. Los tokens push se cifran en backend y se revocan por dispositivo.
--
-- NO afirmar entrega garantizada: push es best-effort; registrar enviada,
-- respuesta del proveedor y entrega confirmada por separado.
-- Realtime no sustituye Web Push/FCM/APNs cuando la app está cerrada.
