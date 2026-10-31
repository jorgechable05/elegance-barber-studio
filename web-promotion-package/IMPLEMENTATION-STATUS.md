# Estado de implementación (actualizado 2026-10-31)

## Verificado
- [x] Rama de trabajo aislada; los cambios están en `feat/servicios-promociones-web`, no en `main`.
- [x] Se añadió paquete separado para futura integración: adaptador Admin, reglas de elegibilidad/cálculo y pruebas unitarias.
- [x] La sintaxis de los módulos JavaScript aislados pasa `node --check`.
- [x] Se consultaron las rutas públicas actuales: `/admin`, `/cliente` y `/pos` responden HTTP 200.
- [x] Se inspeccionó la definición SQL real de `barber_create_reservation`: el precio y nombre se obtienen de una tabla `VALUES` con nueve IDs numéricos y se guardan en `reservas`; no se debe cambiar a UUID ni confiar en precio de navegador.
- [x] Se inspeccionó `barber_admin_create_walkin_sale`: también usa su propio catálogo numérico y guarda el importe en `barber_sales`; queda fuera del alcance hasta diseñar compatibilidad sin afectar POS.
- [x] Las migraciones borrador aún no están aplicadas.

## Bloqueos
- [ ] No se creó rama de desarrollo Supabase. La herramienta cotizó US$0.01344 por hora y requiere confirmación de costo; no se continúa sin autorización expresa.
- [ ] El repositorio tiene wrapper Android pero no la fuente web original versionada de `/admin`, `/cliente`, `/pos`.
- [ ] La suite del paquete necesita ejecutarse en un runtime habilitado y con la zona `America/Merida`; no equivale a pruebas E2E con Supabase.
- [ ] Es necesario diseñar una capa de catálogo compatible o modificar cuidadosamente la RPC para usar servicios administrables, y asegurar que las ventas de mostrador usan el mismo precio promocional correcto si se requiere, sin cambiar el flujo POS actual.
- [ ] El cliente debe obtener promociones para la hora de cita seleccionada; el cálculo y el importe deben validarse y persistirse atómicamente en el backend.
- [ ] La función de sugerencias diarias actual requiere token de sesión; el scheduler necesita una función interna restringida no ejecutable por anon/authenticated.
- [ ] Ejecutar regresión completa y pruebas de extremo a extremo tras integrar.

**No desplegar a producción.** No se han aplicado migraciones, no se modificó Vercel y no se cambió el POS.
