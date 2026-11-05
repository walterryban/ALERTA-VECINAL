# VIGIARED — Alta vecinal mediante QR de manzana y PIN por domicilio v0.3

**Estado:** decisión funcional y propuesta técnica para revisión. No ejecutar SQL ni desplegar.
**Ámbito:** incorporación de vecinos a una vivienda dentro de una manzana/comunidad.
**Presupuesto:** diseño compatible con desarrollo inicial de costo cero; no presupone SMS, WhatsApp ni servicios pagos. **Requisito de acceso vecinal:** cada vecino debe disponer de un teléfono; el correo electrónico es opcional.

## 1. Decisión funcional que recupera el flujo original

VIGIARED utilizará dos elementos distintos:

1. **QR de manzana:** identifica la comunidad/manzana y abre la pantalla de incorporación. No es secreto y no concede acceso por sí solo.
2. **PIN único de domicilio:** lo genera VIGIARED cuando un domicilio es registrado en la plataforma. Es una credencial de incorporación propia de esa vivienda; no es un PIN compartido por toda la manzana ni un PIN diferente para cada vecino.

El QR no contiene el PIN ni datos personales. El vecino escanea el QR correspondiente a su manzana e ingresa el PIN que recibió para su domicilio.

## 2. Alta y emisión del PIN

1. Un administrador autorizado registra la comunidad/manzana y sus domicilios/unidades en VIGIARED.
2. El backend genera automáticamente un PIN aleatorio, único dentro de la plataforma, para cada domicilio.
3. El PIN se entrega al responsable del domicilio mediante un mecanismo controlado (por ejemplo, tarjeta impresa o visualización única para el operador autorizado).
4. La plataforma registra emisión, estado, fecha y unidad asociada, pero nunca escribe el PIN en auditorías, logs ni respuestas posteriores.
5. El PIN puede revocarse y regenerarse. La rotación invalida el anterior y no altera las membresías ya aprobadas.

No se deben importar ni reutilizar PIN de la aplicación heredada. Los registros antiguos y los datos ficticios no son fuente de identidad ni autorización.

## 3. Incorporación de cada vecino

1. La persona escanea el QR de la manzana.
2. La pantalla muestra la comunidad/manzana identificada, sin revelar datos privados de otros domicilios.
3. La persona ingresa el PIN de su vivienda.
4. VIGIARED valida el PIN en el servidor y determina la unidad asociada.
5. La persona debe disponer de un teléfono como requisito indispensable de uso. El correo electrónico es opcional. Se autentica o crea su cuenta individual mediante un método telefónico que se habilitará cuando exista una verificación segura y sostenible a costo cero; el PIN de domicilio no sustituye la autenticación de la persona.
6. El backend crea una solicitud pendiente de membresía para esa cuenta y ese domicilio.
7. El primer titular se habilita solamente después de una verificación independiente y auditable por un procedimiento autorizado. El QR y el PIN por sí solos nunca asignan la titularidad.
8. Una vez que exista un titular activo, las solicitudes de otros integrantes de esa vivienda se aprueban o rechazan por un titular activo de la misma unidad.
9. Cada persona conserva su propia cuenta y membresía revocable. Compartir el PIN del domicilio no comparte cuentas ni permisos.

## 4. Separación de conceptos

- QR = identifica la manzana.
- PIN = demuestra que la persona dispone de la credencial de incorporación del domicilio y permite presentar una solicitud.
- Cuenta Auth = identifica la cuenta individual de acceso.
- Perfil vecinal = representa a la persona.
- Membresía = autoriza a esa persona en un domicilio/unidad concreto.
- Titularidad = rol que solo se otorga mediante el procedimiento de verificación autorizado.

El PIN no sustituye la autenticación individual. No debe permitir consultar alertas, domicilios, datos personales, fichas ni información de otros integrantes antes de que la membresía sea aprobada.

## 5. Requisitos de seguridad del PIN

- Generación criptográficamente segura en backend; nunca desde JavaScript del navegador.
- Valor aleatorio de longitud suficiente para uso humano (definir longitud final en la revisión de seguridad y usabilidad).
- Unicidad global entre credenciales activas; no derivarlo de dirección, manzana, teléfono ni secuencias predecibles.
- No incluir el PIN dentro del QR, URL, parámetros, logs, auditoría ni analítica.
- No almacenar PIN numérico con SHA-256 simple: por su baja entropía, se requiere verificación mediante HMAC con secreto servidor protegido o un esquema de hash resistente a fuerza bruta, con gestión segura de claves.
- Comparación en backend y respuesta genérica para evitar enumeración de domicilios.
- Límites de intentos y demoras progresivas, con controles por origen y credencial. Evitar bloqueos permanentes que permitan a terceros impedir el acceso de una vivienda.
- Auditoría de emisión, uso, intentos rechazados, revocación y regeneración, sin registrar el valor del PIN.
- Revocación y rotación transaccionales; un PIN anterior no debe seguir siendo válido.
- El QR de manzana puede ser público y compartible; la seguridad no depende de ocultarlo.

## 6. Privacidad e inclusión

- No mostrar el domicilio exacto antes de validar el PIN, salvo la información mínima necesaria para que la persona reconozca la manzana.
- Interfaz con tipografía ampliable, alto contraste, etiquetas para lectores de pantalla, navegación por teclado y botones grandes.
- Campo PIN con opción de mostrar/ocultar, pegado permitido, lectura accesible y mensajes de error claros.
- No exigir correo electrónico ni correo prestado: el teléfono es obligatorio para el uso vecinal y el correo es opcional. No recopilar diagnósticos médicos.
- Ofrecer instrucciones impresas simples para personas mayores y personas con discapacidad.
- El teléfono es obligatorio para el uso vecinal; el correo es opcional. Los canales de verificación (SMS/WhatsApp) se evaluarán por costo y viabilidad. El QR + PIN identifica manzana y domicilio, pero no reemplaza la autenticación individual.

## 7. Compatibilidad con identidad individual v0.2

Se conserva la separación de cuenta, perfil y membresía de la arquitectura v0.2, así como RLS, RPC de confianza, auditoría y aislamiento por unidad. Sin embargo, el mecanismo de invitación genérica por token de un titular no reemplaza el PIN generado por VIGIARED para cada domicilio.

La documentación v0.2 que afirma que el QR nunca se acompaña de un PIN de domicilio queda supersedida en ese punto por esta decisión v0.3. Las invitaciones individuales podrán seguir existiendo como mecanismo administrativo adicional, pero no como sustituto del ingreso original QR de manzana + PIN de vivienda.

## 8. Bloqueos que deben resolverse antes de implementar

1. Inspeccionar el esquema real de establecimientos/unidades en el proyecto actual, sin modificarlo.
2. Diseñar tabla/entidad de credenciales de domicilio vinculada a una unidad, con hash/HMAC, estado, emisión, vencimiento opcional y rotación.
3. Diseñar RPC/Edge Function para validar el PIN y crear una solicitud pendiente sin revelar si otros domicilios existen.
4. Definir el procedimiento verificable de alta del primer titular.
5. Resolver cómo autenticar individualmente a una persona que tiene teléfono pero no correo electrónico. El teléfono es requisito indispensable para el uso vecinal; el correo es opcional. El PIN de vivienda no puede hacerse pasar por prueba de identidad personal. Evaluar una verificación telefónica realmente gratuita antes de habilitar Phone; no activar SMS/WhatsApp pagos ni asumir que un mensaje entrante equivale automáticamente a una identidad verificada.
6. Definir aprobación de integrantes adicionales, recuperación de cuenta y transferencia de titularidad.
7. Crear pruebas automatizadas de fuerza bruta, concurrencia, PIN revocado, PIN repetido, aislamiento entre domicilios y solicitudes duplicadas.
8. Ensayar en un proyecto Supabase aislado y con domicilios ficticios antes de integrar la terminal.

## 9. Restricciones operativas

- No ejecutar este documento como SQL.
- No modificar el proyecto Supabase compartido ni producción.
- No desplegar la terminal vecinal hasta superar la revisión y las pruebas.
- No habilitar Phone ni contratar SMS/WhatsApp sin evaluación de costo y autorización expresa.
- No usar datos históricos o ficticios como identidades reales.
