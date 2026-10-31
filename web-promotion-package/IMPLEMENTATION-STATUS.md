# Estado de implementación (actualizado 2026-10-31)

## Comprobaciones realizadas
- [x] La rama de trabajo permanece separada de `main`.
- [x] Paquete Admin de servicios/promociones y utilidades de aplicabilidad/precio añadidos por separado.
- [x] Las rutas productivas `/admin`, `/cliente` y `/pos` responden HTTP 200 en comprobación de lectura.
- [x] Inspeccionada la RPC real `barber_create_reservation`: toma `p_servicio_id` como entero 1–9, obtiene nombre/precio de un catálogo `VALUES` incorporado a la función y guarda el importe en `reservas`.
- [x] Inspeccionada `barber_admin_create_walkin_sale`: usa su propio catálogo numérico fijo; POS no debe cambiarse sin una prueba específica.
- [x] Los borradores SQL aún no se aplican.
- [x] Pruebas unitarias de utilidades ejecutadas en Node 22 con `TZ=America/Merida`: 7/7 pasan tras validar manualmente la lógica de zona horaria.

## Bloqueos de integración
- [ ] Este repositorio contiene un wrapper Android, pero no la fuente web original versionada de `/admin`, `/cliente` ni `/pos`.
- [ ] La herramienta de Supabase informa un costo de US$0.01344 por hora para crear una rama de desarrollo; requiere confirmación de costo antes de poder probar migraciones aisladas.
- [ ] Hay que resolver la clave de compatibilidad entre servicios UUID nuevos e IDs numéricos 1–9 antes de conectar catálogo y reservas.
- [ ] El descuento debe validarse y guardarse transaccionalmente en backend al crear una reserva; no debe confiarse en el navegador.
- [ ] Debe resolverse si los precios de reserva admiten centavos: `reservas.precio` es `integer` en la base actual, mientras que el helper de promociones calcula dos decimales.
- [ ] El generador diario de sugerencias de borrador requiere un token interactivo; un scheduler necesita una función interna segura, no ejecutable por usuarios anónimos.
- [ ] Ejecutar regresión Admin/Cliente/POS completa con entorno aislado y pruebas de extremo a extremo.

**No desplegar a producción.** No se aplicaron migraciones, no se cambió el despliegue Vercel y no se modificó POS.
