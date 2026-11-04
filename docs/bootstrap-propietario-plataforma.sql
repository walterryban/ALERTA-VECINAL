-- ALERTA VECINAL PRO
-- ALTA INICIAL DEL PROPIETARIO DE PLATAFORMA
-- PLANTILLA: NO EJECUTAR HASTA:
--   1) Revisar y probar RBAC v0.1 en un proyecto Supabase aislado.
--   2) Aplicar v0.1 de forma aprobada en el proyecto destino.
--   3) Crear y confirmar por correo la cuenta Auth que será propietaria.
--   4) Reemplazar el correo de ejemplo por el correo exacto de esa cuenta.
--
-- Este script NO crea usuarios, NO crea organizaciones y NO toca alertas,
-- manzanas, vecinos ni vendedores. Solo registra una identidad Auth existente
-- como propietaria global. No pegar contraseñas, tokens ni claves aquí.

DO $bootstrap$
DECLARE
  v_email text := lower(trim('REEMPLAZAR_POR_EL_CORREO_EXACTO_DEL_PROPIETARIO'));
  v_user_ids uuid[];
  v_user_id uuid;
BEGIN
  IF to_regclass('public.propietarios_plataforma') IS NULL THEN
    RAISE EXCEPTION 'Falta public.propietarios_plataforma. Aplicar y verificar RBAC v0.1 primero.';
  END IF;

  IF v_email = ''
     OR v_email = 'reemplazar_por_el_correo_exacto_del_propietario' THEN
    RAISE EXCEPTION 'Reemplazá el correo de ejemplo por el correo exacto de la cuenta Auth propietaria.';
  END IF;

  SELECT array_agg(u.id)
    INTO v_user_ids
  FROM (
    SELECT id
    FROM auth.users
    WHERE lower(email) = v_email
    LIMIT 2
  ) AS u;

  IF COALESCE(array_length(v_user_ids, 1), 0) = 0 THEN
    RAISE EXCEPTION 'No existe una cuenta Auth con ese correo. Creala y confirmala antes de continuar.';
  ELSIF array_length(v_user_ids, 1) > 1 THEN
    RAISE EXCEPTION 'La búsqueda no fue única. No se registró ningún propietario.';
  END IF;

  v_user_id := v_user_ids[1];

  IF EXISTS (SELECT 1 FROM public.propietarios_plataforma) THEN
    IF EXISTS (
      SELECT 1
      FROM public.propietarios_plataforma
      WHERE auth_user_id = v_user_id
        AND activo = true
    ) THEN
      RAISE NOTICE 'Esta cuenta ya está registrada como propietaria activa. No se realizaron cambios.';
      RETURN;
    END IF;

    RAISE EXCEPTION 'Ya existe al menos un propietario registrado. Detenerse y revisar antes de modificar el control global.';
  END IF;

  INSERT INTO public.propietarios_plataforma (auth_user_id, activo)
  VALUES (v_user_id, true);

  RAISE NOTICE 'Propietario inicial registrado. No se creó ninguna organización.';
END
$bootstrap$;

-- Verificación posterior (solo lectura):
-- SELECT p.auth_user_id, p.activo, p.creado_at
-- FROM public.propietarios_plataforma AS p;
