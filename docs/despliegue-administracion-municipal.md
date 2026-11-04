# Despliegue controlado de administración municipal

Esta guía corresponde a la rama `integracion-segura-2026-11-04`. No ejecutar contra producción hasta completar pruebas en un proyecto Supabase aislado.

## Dependencias

1. Revisar y aplicar primero `docs/migracion-rbac-plataforma-municipios-v0.1-borrador.sql`.
2. Revisar y aplicar después `docs/migracion-rbac-plataforma-municipios-v0.2-borrador.sql`.\n3. Revisar y aplicar luego `docs/migracion-rbac-plataforma-municipios-v0.3-borrador.sql` para retirar políticas heredadas globales y aislar alertas/manzanas por organización.
4. Crear/activar una organización municipal y registrar el UUID Auth del propietario en `public.propietarios_plataforma` mediante un procedimiento administrativo fuera del navegador.
5. Crear la membresía inicial del administrador municipal después de verificar su cuenta e identidad.
6. Confirmar que RLS y RPC operativas ya restringen los datos por organización antes de habilitar la consola multi-municipal.

## Interfaz web\n\nLa página `administracion.html` permite al propietario crear organizaciones y gestionar operadores; el administrador municipal gestiona únicamente los operadores de su organización. El enlace está disponible desde la página inicial. La página requiere una sesión Auth y las RPC RBAC aplicadas. La consola `admin.html` consulta el contexto RBAC, muestra alertas según las políticas RLS y exige seleccionar una organización al crear manzanas.\n\n## Edge Function

La función `supabase/functions/administrar-operadores/index.ts` ofrece acciones:
- `list`: listar membresías de la organización autorizada.
- `invite`: enviar invitación por correo; crea membresía en estado `pendiente`.
- `activate`: activar solo cuando Supabase Auth confirma el correo.
- `change_role`: cambiar un rol dentro de los límites del actor.
- `revoke`: revocar una membresía sin borrar la identidad Auth ni afectar otras organizaciones.\n- `create_organization`: crear una organización activa, acción exclusiva del propietario.

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

- El aislamiento multi-municipal solo queda activo después de aplicar y probar v0.3. Antes de eso, la consola mantiene compatibilidad temporal con `es_operador()`.
- La función no incorpora todavía vinculación de cuentas Auth ya existentes ni gestión de MFA. Para cuentas existentes se requiere un flujo separado, sin duplicar usuarios.
- La auditoría se inserta después de la operación de Auth/DB; ante error de auditoría la función devuelve una advertencia explícita para revisión.
- No se crearon usuarios, invitaciones, organizaciones ni membresías con estos commits. El código está en la rama de integración y la vista previa de Vercel compila, pero la Edge Function aún debe desplegarse en Supabase y las migraciones no están aplicadas.
