# Revisión estática de seguridad — identidad vecinal v0.2

**Estado:** revisión estática del borrador; no equivale a compilación PostgreSQL, auditoría externa ni prueba funcional.  
**Archivo revisado:** `docs/migracion-identidad-vecinal-v0.2-borrador.sql`

## Correcciones incorporadas durante esta revisión

1. Se corrigieron delimitadores PL/pgSQL de la función de revocación de invitación.
2. Se corrigieron separadores residuales en el bloque de permisos SQL.
3. El estado `pendiente` quedó incluido en la restricción de estados de membresía, coherente con su valor predeterminado.
4. El provisionamiento y el bootstrap rechazan perfiles suspendidos o bloqueados.
5. La aprobación comprueba que la unidad y el establecimiento estén activos.
6. La aprobación impide que una cuenta apruebe su propia solicitud.
7. Se mantuvieron RLS y la revocación de privilegios directos en las cinco tablas nuevas.
8. El bootstrap y el provisionamiento se reservan a `service_role`; las RPC de usuario se conceden a `authenticated`.

## Resultado de comprobaciones estáticas

- Cinco tablas nuevas definidas.
- RLS activado en las cinco tablas.
- Nueve funciones con permisos explícitos en el bloque final.
- Delimitadores de funciones revisados después de las correcciones.
- No se encontraron los patrones de delimitador incompleto que se habían detectado durante la revisión.

Estas comprobaciones son inspecciones de texto, no validación del parser de PostgreSQL. El archivo todavía **no fue ejecutado** ni compilado en una instancia PostgreSQL.

## Riesgos y tareas pendientes

- Revisar el propietario efectivo de cada función `SECURITY DEFINER` y confirmar que sea un rol confiable, no modificable por usuarios de aplicación.
- Probar permisos efectivos de `service_role`, `authenticated` y `anon` en Supabase aislado.
- Diseñar y probar la transferencia de titularidad; el borrador protege al último titular, pero no implementa la transferencia.
- Implementar consulta segura y limitada de solicitudes pendientes para titulares; no se habilita SELECT directo.
- Definir cancelación de solicitudes y recuperación de cuenta/titularidad.
- Incorporar límites de intentos de canje y defensa contra abuso a nivel RPC/Edge Function.
- Verificar que la referencia de bootstrap apunte a un expediente externo válido; el texto guardado no demuestra por sí mismo que la verificación ocurrió.
- Probar carreras concurrentes en canje, aprobación, bootstrap y revocación.
- Verificar compatibilidad real con el esquema base de `establecimientos` y `unidades`.
- Revisar protección de datos personales, retención y procedimiento para menores/tutores.

## Matriz de pruebas obligatoria

| Prueba | Resultado esperado |
|---|---|
| Anónimo ejecuta RPC protegida | Denegado |
| Authenticated intenta provisionar perfil | Denegado |
| Authenticated intenta inicializar titular | Denegado |
| Service role provisiona cuenta confirmada | Perfil creado o recuperado |
| Cuenta sin confirmar intenta bootstrap | Denegado |
| Perfil bloqueado intenta bootstrap/provisionamiento | Denegado |
| Perfil A solicita ingreso con invitación válida | Solicitud pendiente |
| Reutilización concurrente del mismo token | Como máximo un canje |
| Cuenta titular aprueba su propia solicitud | Denegado |
| Titular de otra unidad aprueba | Denegado |
| Titular aprueba unidad suspendida | Denegado |
| Revocar membresía en unidad A | No afecta unidad B |
| Revocar último titular | Denegado |
| Consulta de contexto sin membresía activa | Sin resultados |
| Consulta de contexto de otra cuenta | Imposible por contrato de RPC |

## Decisión

El v0.2 es una base de diseño más coherente que los borradores v0.1, pero todavía no está listo para producción ni para conectar la terminal. El siguiente paso técnico debe ser construir pruebas automatizadas y ejecutar el SQL únicamente en un proyecto Supabase desechable, una vez que exista y se haya autorizado expresamente.
