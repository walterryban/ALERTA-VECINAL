-- ALERTA VECINAL PRO
-- BORRADOR DE ENDURECIMIENTO INICIAL — NO EJECUTAR SIN APROBACIÓN
-- Fecha de revisión: 2026-11-04
--
-- HALLAZGOS CONFIRMADOS:
--   public.vecinos: RLS deshabilitado; anon/authenticated tienen privilegios.
--   public.vendedores: RLS deshabilitado; anon/authenticated tienen privilegios.
--   No existen políticas RLS para ninguna de las dos tablas.
--   La inspección del código de esta rama no encontró consultas directas
--   a estas tablas desde terminal.html, admin.html, index.html ni
--   generador_credenciales.html.
--
-- IMPORTANTE:
--   RLS controla acceso por fila, pero NO sustituye los privilegios SQL.
--   En particular, TRUNCATE, REFERENCES y TRIGGER no quedan protegidos
--   por las políticas RLS. Por eso el borrador revoca todos los privilegios
--   directos a anon Y authenticated, además de PUBLIC.
--
-- IMPACTO PREVISTO:
--   Los navegadores anon/authenticated no podrán acceder directamente a
--   vecinos ni vendedores hasta que se diseñen y autoricen RPC/políticas
--   específicas. Esto puede afectar otros clientes o integraciones que no
--   estén en este repositorio; deben identificarse antes de aplicar.
--   No se revocan privilegios de service_role ni de postgres.
--   Las funciones SECURITY DEFINER deben auditarse por separado: pueden
--   acceder a estas tablas según su propietario y su código.
--
-- NO EJECUTAR EN PRODUCCIÓN todavía.
-- Antes: backup, inventario de clientes/integraciones, revisión de funciones,
-- prueba en un proyecto Supabase aislado y aprobación explícita.
--
-- Este script no borra ni actualiza filas, no elimina columnas y no toca
-- alertas, manzanas, operadores ni otras tablas. Los datos existentes de
-- manzanas y alertas son ficticios de prueba.

BEGIN;

REVOKE ALL PRIVILEGES ON TABLE public.vecinos
  FROM PUBLIC, anon, authenticated;

REVOKE ALL PRIVILEGES ON TABLE public.vendedores
  FROM PUBLIC, anon, authenticated;

ALTER TABLE public.vecinos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vendedores ENABLE ROW LEVEL SECURITY;

COMMIT;

-- VERIFICACIÓN SOLO LECTURA (ejecutar después de una prueba controlada):
-- 1) Estado RLS:
SELECT
  n.nspname AS esquema,
  c.relname AS tabla,
  c.relrowsecurity AS rls_habilitado,
  c.relforcerowsecurity AS rls_forzado,
  pg_get_userbyid(c.relowner) AS propietario
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('vecinos','vendedores')
ORDER BY c.relname;

-- 2) Privilegios que permanecen para roles de aplicación:
SELECT
  grantee, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name IN ('vecinos','vendedores')
  AND grantee IN ('anon','authenticated','service_role')
ORDER BY table_name, grantee, privilege_type;

-- 3) Políticas RLS:
SELECT
  tablename, policyname, cmd, roles
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('vecinos','vendedores')
ORDER BY tablename, policyname;

-- NOTA:
-- No se incluye reversión automática. No restaurar GRANT ALL a anon.
-- Los permisos futuros deben concederse por operación mínima y solo después
-- de implementar autorización de servidor, RPC revisadas y pruebas.
