-- ALERTA VECINAL PRO
-- INSPECCION DE IDENTIDAD Y HASH — SOLO LECTURA
-- Ejecutar en Supabase SQL Editor. No modifica datos ni estructura.

-- 1) Version de PostgreSQL y extensiones disponibles.
SELECT
  current_setting('server_version') AS postgres_version,
  e.extname AS extension_name,
  e.extversion AS extension_version,
  n.nspname AS extension_schema
FROM pg_extension e
JOIN pg_namespace n ON n.oid = e.extnamespace
ORDER BY e.extname;

-- 2) Disponibilidad de funciones criptograficas relevantes.
SELECT
  to_regprocedure('public.digest(bytea,text)') AS public_digest,
  to_regprocedure('extensions.digest(bytea,text)') AS extensions_digest,
  to_regprocedure('public.gen_random_uuid()') AS public_gen_random_uuid,
  to_regprocedure('pg_catalog.gen_random_uuid()') AS catalog_gen_random_uuid;

-- 3) Confirmar la tabla Auth sin consultar ni mostrar usuarios.
SELECT
  to_regclass('auth.users') AS auth_users_table,
  to_regclass('auth.identities') AS auth_identities_table;

-- 4) Ver columnas de vecinos para confirmar el estado actual del modelo.
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'vecinos'
ORDER BY ordinal_position;

-- 5) Verificar si vecinos ya tiene vinculo con un usuario Auth.
SELECT
  c.conname AS constraint_name,
  pg_get_constraintdef(c.oid) AS definition
FROM pg_constraint c
WHERE c.conrelid = 'public.vecinos'::regclass
ORDER BY c.conname;

-- 6) Verificar funciones hash disponibles en esquemas visibles.
SELECT
  n.nspname AS schema_name,
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS arguments,
  pg_get_function_result(p.oid) AS result_type
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE p.proname IN ('digest', 'hmac', 'crypt', 'gen_random_bytes')
ORDER BY n.nspname, p.proname;

-- No devuelve emails, teléfonos, nombres ni filas de personas.
