-- VIGIARED v0.3 — consultas seguras para gestión territorial
-- Lecturas autorizadas mediante SECURITY DEFINER; no se conceden SELECT directos.

begin;

create or replace function public.listar_organizaciones_gestionables()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_es_propietario boolean;
  v_resultado jsonb;
begin
  if v_actor is null then
    raise exception 'Autenticación requerida';
  end if;

  select exists (
    select 1
    from public.propietarios_plataforma pp
    where pp.user_id = v_actor and pp.activo = true
  ) into v_es_propietario;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'organizacion_id', o.id,
        'nombre', o.nombre,
        'tipo', o.tipo,
        'slug', o.slug,
        'estado', o.estado,
        'rol_acceso', case
          when v_es_propietario then 'propietario_plataforma'
          else 'administrador_organizacion'
        end,
        'created_at', o.created_at
      )
      order by o.nombre, o.created_at
    ),
    '[]'::jsonb
  )
  into v_resultado
  from public.organizaciones o
  where v_es_propietario
     or exists (
       select 1
       from public.membresias_organizacion mo
       where mo.organizacion_id = o.id
         and mo.user_id = v_actor
         and mo.rol = 'administrador_organizacion'
         and mo.estado = 'activa'
     );

  return jsonb_build_object(
    'ok', true,
    'es_propietario_plataforma', v_es_propietario,
    'organizaciones', v_resultado
  );
end;
$$;

create or replace function public.listar_manzanas_organizacion(
  p_organizacion_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_manzanas jsonb;
begin
  if v_actor is null then
    raise exception 'Autenticación requerida';
  end if;

  if p_organizacion_id is null
     or not public._vigiared_puede_administrar_org(p_organizacion_id, v_actor) then
    raise exception 'No autorizado para consultar esta organización';
  end if;

  if not exists (
    select 1 from public.organizaciones o
    where o.id = p_organizacion_id
  ) then
    raise exception 'Organización no disponible';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'manzana_vigiared_id', m.id,
        'qr_public_id', m.public_id,
        'nombre', m.nombre,
        'estado', m.estado,
        'created_at', m.created_at,
        'domicilios_activos', (
          select count(*)::integer
          from public.unidades u
          where u.organizacion_id = m.organizacion_id
            and u.manzana_vigiared_id = m.id
            and u.estado = 'activa'
        )
      )
      order by m.nombre, m.created_at
    ),
    '[]'::jsonb
  )
  into v_manzanas
  from public.manzanas_vigiared m
  where m.organizacion_id = p_organizacion_id;

  return jsonb_build_object(
    'ok', true,
    'organizacion_id', p_organizacion_id,
    'manzanas', v_manzanas
  );
end;
$$;

revoke all on function public.listar_organizaciones_gestionables()
  from public, anon, authenticated, service_role;
revoke all on function public.listar_manzanas_organizacion(uuid)
  from public, anon, authenticated, service_role;

grant execute on function public.listar_organizaciones_gestionables()
  to authenticated;
grant execute on function public.listar_manzanas_organizacion(uuid)
  to authenticated;

comment on function public.listar_organizaciones_gestionables() is
  'Lista organizaciones para propietario global o administrador activo; no expone SELECT directo.';
comment on function public.listar_manzanas_organizacion(uuid) is
  'Lista manzanas sólo al propietario global o administrador activo de esa organización.';

commit;
