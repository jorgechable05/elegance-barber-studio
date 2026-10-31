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
