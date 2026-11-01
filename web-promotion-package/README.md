# Paquete aislado de integración — Servicios y promociones

> **NO DESPLEGAR A PRODUCCIÓN.** Este paquete se revisa por separado; no sustituye ni modifica las páginas activas `/admin`, `/cliente` o `/pos`.

## Contenido
- `admin-promotions.js`: componente desacoplado para montar una nueva sección del administrador después del login existente.
- `customer-promotion-utils.js`: validación de promoción por servicio, vigencia, día y horario local de Pisté, Yucatán, así como cálculo de descuento.
- `customer-promotion-utils.test.mjs` y `smoke-tests.mjs`: pruebas unitarias aisladas.

## Pruebas locales
En Node.js 22 o superior:
```sh
npm test
```
El comando fija la zona horaria del negocio como `America/Merida`.

## Bloqueos antes de conectar
- El repositorio no contiene fuente versionada de las páginas web. No pegar ni sustituir estas páginas a ciegas.
- El cliente real usa IDs numéricos de servicios del 1 al 9; la migración propuesta usa UUID, falta la correspondencia.
- El descuento debe validarse y aplicarse en el backend al crear la reserva. El navegador solo muestra el cálculo; no decide el importe persistido.
- Solo promociones aprobadas y elegibles por fecha/hora/servicio se publican. Las sugerencias automáticas permanecen pendientes.
- No cambiar RPC de venta/POS y no recalcular citas existentes.

## Pruebas de navegador aisladas
El workflow de GitHub Actions instala Playwright/Chromium y ejecuta `browser-smoke-tests.mjs`. Estas pruebas sirven las vistas recuperadas desde un servidor local y sustituyen todas las respuestas RPC por fixtures. Incluyen montaje del panel Admin, visualización de una promoción en Cliente y flujo de mostrador/ticket en POS. Se bloquea cualquier tráfico externo que no sea parte del servidor local y se afirma que no haya solicitudes al Supabase productivo.

**Límite:** estas pruebas no autentican contra Supabase real, no crean registros de verdad ni sustituyen las pruebas end-to-end que requieren un proyecto de Elegance no productivo. Mantener pendiente la certificación integrada hasta probar las RPC reales en ese entorno aislado.
