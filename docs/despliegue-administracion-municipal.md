# Despliegue controlado de administración municipal

Esta guía corresponde a la rama `integracion-segura-2026-11-04`. No ejecutar contra producción hasta completar pruebas en un proyecto Supabase aislado.

## Dependencias

1. Revisar y aplicar primero `docs/migracion-rbac-plataforma-municipios-v0.1-borrador.sql`.
2. Revisar y aplicar después `docs/migracion-rbac-plataforma-municipios-v0.2-borrador.sql`.
3. Crear/activar una organización municipal y registrar el UUID Auth del propietario en `public.propietarios_plataforma` mediante un procedimiento administrativo fuera del navegador.
4. Crear la membresía inicial del administrador municipal después de verificar su cuenta e identidad.
5. Confirmar que RLS y RPC operativas ya restringen los datos por organización antes de habilitar la consola multi-municipal.

## Edge Function

La función `supabase/functions/administrar-operadores/index.ts` ofrece acciones:
- `list`: listar membresías de la organización autorizada.
- `invite`: enviar invitación por correo; crea membresía en estado `pendiente`.
- `activate`: activar solo cuando Supabase Auth confirma el correo.
- `change_role`: cambiar un rol dentro de los límites del actor.
- `revoke`: revocar una membresía sin borrar la identidad Auth ni afectar otras organizaciones.

La función valida el JWT del usuario, consulta el contexto y la autorización RBAC mediante RPC y usa la clave service role exclusivamente en el entorno Edge. La cuenta propietaria está protegida frente a revocación municipal.

## Secretos y configuración

Supabase proporciona `SUPABASE_URL`, `SUPABASE_ANON_KEY` y `SUPABASE_SERVICE_ROLE_KEY` al runtime de Edge Functions. Nunca copiar la clave service role a HTML, JavaScript del navegador, GitHub ni Vercel público.

Configurar además:
- `APP_ORIGIN`: origen exacto autorizado, por ejemplo el dominio de producción o el de preview usado en pruebas.
- `AUTH_REDIRECT_URL`: URL permitida en Supabase Auth a la que vuelve la invitación para establecer contraseña.

No se incluyeron valores secretos en el repositorio.

## Despliegue (solo entorno de pruebas)

Desde un entorno con Supabase CLI vinculado al proyecto de pruebas:

```bash
supabase functions deploy administrar-operadores
supabase secrets set APP_ORIGIN=https://TU-DOMINIO-DE-PRUEBA
supabase secrets set AUTH_REDIRECT_URL=https://TU-DOMINIO-DE-PRUEBA
```

No ejecutar estos comandos contra producción durante esta etapa.

## Flujo operativo

- El propietario registra inicialmente la organización y la cuenta de administrador por un procedimiento controlado.
- El administrador municipal invita operadores por correo nominativo.
- La membresía queda pendiente hasta que la persona confirma el correo.
- Luego un administrador autorizado activa el acceso.
- La baja revoca la membresía municipal, no elimina la cuenta Auth de la persona; si pertenece a otro municipio, conserva únicamente los accesos independientes que correspondan.
- Cada cambio se registra en `auditoria_administrativa`.

## Límites actuales

- El borrador RBAC no reemplaza aún las políticas heredadas de `alertas` y `manzanas`; por eso todavía no debe anunciarse aislamiento multi-municipal completo.
- La función no incorpora todavía vinculación de cuentas Auth ya existentes ni gestión de MFA. Para cuentas existentes se requiere un flujo separado, sin duplicar usuarios.
- La auditoría se inserta después de la operación de Auth/DB; ante error de auditoría la función devuelve una advertencia explícita para revisión.
- No se crearon usuarios, invitaciones, organizaciones ni membresías con este commit.
