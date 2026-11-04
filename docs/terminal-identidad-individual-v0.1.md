# VIGIARED — Terminal de identidad individual v0.1

Estado: interfaz de desarrollo incorporada a `terminal.html`. No habilitada para altas ni alertas reales.

## Cambios aplicados

- Se retiró de la terminal de desarrollo el formulario de manzana/PIN compartido.
- Se eliminó el envío de datos personales desde el navegador mediante la RPC heredada `crear_alerta`.
- La pantalla presenta el modelo de cuenta individual, invitación de un solo uso y aprobación por unidad.
- Los controles de ingreso, registro y canje permanecen deshabilitados deliberadamente.
- No se inicializa Supabase ni se realizan escrituras/lecturas contra el proyecto compartido.
- La interfaz aclara que no debe introducirse una contraseña real mientras el backend no esté conectado a un entorno aislado.

## Por qué los controles siguen deshabilitados

Los borradores actuales de identidad v0.1 todavía dependen de `public.vecinos` como ficha canónica. La revisión v0.2 recomienda separar cuenta, perfil y membresía para permitir que una persona tenga varias unidades sin duplicar identidad. Antes de habilitar Auth o canje de invitaciones hay que publicar un esquema v0.2 coherente y sus RPC compatibles.

## Próxima integración técnica

1. Diseñar migración de perfiles y membresías por unidad, sin usar `vecinos` como fuente de autorización.
2. Diseñar bootstrap verificado del primer titular.
3. Implementar Auth individual en proyecto Supabase aislado.
4. Implementar alta/canje/aprobación/revocación contra el nuevo modelo.
5. Implementar RPC de contexto autenticado y pruebas negativas entre unidades.
6. Implementar creación de alertas con identidad/unidad resueltas en servidor.
7. Habilitar interfaz únicamente tras aprobar pruebas funcionales y de seguridad.

## Verificación

La revisión debe confirmar que la terminal no contiene llamadas a `validar_acceso` ni `crear_alerta`, no solicita PIN compartido y no contiene credenciales privilegiadas. El despliegue de preview existente comparte la base actual; no debe usarse para pruebas de escritura.
