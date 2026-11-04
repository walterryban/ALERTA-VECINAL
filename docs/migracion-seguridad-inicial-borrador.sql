-- ALERTA VECINAL PRO
-- BORRADOR DE ENDURECIMIENTO INICIAL — NO EJECUTAR SIN APROBACIÓN
--
-- Hallazgos confirmados el 04-11-2026:
--   public.vecinos: RLS deshabilitado; anon tiene privilegios de tabla.
--   public.vendedores: RLS deshabilitado; anon tiene privilegios de tabla.
--   La inspección del código de la rama encontró que terminal.html,
--   admin.html, index.html y generador_credenciales.html no consultan
--   directamente estas dos tablas.
--
-- IMPACTO:
--   Este cambio quita acceso directo de anon y activa RLS sin crear políticas.
--   Por diseño, anon y authenticated quedarán sin acceso directo a estas
--   tablas hasta que existan RPC/políticas expresamente revisadas.
--   Las funciones SECURITY DEFINER propiedad de postgres y service_role
--   pueden seguir operando según sus propios permisos; deben auditarse.
--
-- No borra registros, columnas ni tablas. No modifica las 28 alertas,
-- las 3 manzanas ni el registro existente de vendedores.
--
-- Antes de ejecutar:
--   1. Confirmar que no haya otros clientes o integraciones que lean/escriban
--      vecinos o vendedores directamente.
--   2. Hacer backup/exportación de la base.
--   3. Probar primero en un proyecto Supabase de prueba.
--   4. Autorizar expresamente la aplicación en el proyecto real.

BEGIN;

REVOKE ALL PRIVILEGES ON TABLE public.vecinos FROM anon, PUBLIC;
REVOKE ALL PRIVILEGES ON TABLE public.vendedores FROM anon, PUBLIC;

ALTER TABLE public.vecinos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vendedores ENABLE ROW LEVEL SECURITY;

COMMIT;

-- VERIFICACIÓN POSTERIOR (solo lectura):
SELECT
  n.nspname AS esquema,
  c.relname AS tabla,
  c.relrowsecurity AS rls_habilitado,
  c.relforcerowsecurity AS rls_forzado
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('vecinos','vendedores')
ORDER BY c.relname;

SELECT
  grantee, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name IN ('vecinos','vendedores')
  AND grantee IN ('anon','authenticated','service_role')
ORDER BY table_name, grantee, privilege_type;

-- NOTA DE REVERSIÓN:
-- No se incluye un GRANT de reversión automático porque volver a otorgar
-- acceso anónimo sin políticas reabriría la exposición detectada.
-- Si hubiera que revertir, primero revisar el impacto y definir permisos
-- mínimos por operación y rol; no restaurar GRANT ALL a anon.
