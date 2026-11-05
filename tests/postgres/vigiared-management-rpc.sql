-- Pruebas de aislamiento de las RPC de gestión VIGIARED.
insert into auth.users(id,phone,phone_confirmed_at) values
 ('33333333-3333-4333-8333-333333333333','+5491100000003',now()),
 ('44444444-4444-4444-8444-444444444444',null,null);

insert into public.membresias_organizacion(organizacion_id,user_id,rol,estado)
values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        '33333333-3333-4333-8333-333333333333',
        'administrador_organizacion','activa');

-- Propietario global: ve las dos organizaciones de prueba.
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
set role authenticated;
select jsonb_array_length(public.listar_organizaciones_gestionables()->'organizaciones') as orgs_propietario \gset
reset role;
do $owner_list$
begin
  if :'orgs_propietario'::integer <> 2 then
    raise exception 'El propietario global debe ver ambas organizaciones';
  end if;
end
$owner_list$;

-- Administrador: sólo ve su organización y sus manzanas.
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
set role authenticated;
select jsonb_array_length(public.listar_organizaciones_gestionables()->'organizaciones') as orgs_admin \gset
select (public.listar_manzanas_organizacion('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')->'manzanas'->0->>'nombre') as manzana_admin \gset
reset role;
do $admin_list$
begin
  if :'orgs_admin'::integer <> 1 then raise exception 'El administrador debe ver sólo su organización'; end if;
  if :'manzana_admin' <> 'Manzana de otra organización' then raise exception 'No se pudo listar la manzana propia'; end if;
end
$admin_list$;

-- No puede consultar manzanas de otra organización.
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
set role authenticated;
do $admin_isolation$
begin
  begin
    perform public.listar_manzanas_organizacion('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  exception when others then
    if sqlerrm = 'No autorizado para consultar esta organización' then return; end if;
    raise;
  end;
  raise exception 'El administrador pudo consultar manzanas de otra organización';
end
$admin_isolation$;
reset role;

-- Cuenta autenticada sin rol: no ve organizaciones ni puede listar manzanas.
select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
set role authenticated;
select jsonb_array_length(public.listar_organizaciones_gestionables()->'organizaciones') as orgs_sin_rol \gset
reset role;
do $no_access$
begin
  if :'orgs_sin_rol'::integer <> 0 then raise exception 'Cuenta sin rol vio organizaciones'; end if;
end
$no_access$;

select 'OK: aislamiento de RPC de gestión superado' as resultado;
