# Verificación de empaquetado para integración aislada

Este proyecto contiene vistas recuperadas en `web-recovery/`, no prueba que los archivos desplegados en producción tengan la misma estructura. Este chequeo está pensado para bloquear una futura integración si las dependencias relativas no se empaquetan junto a la vista.

- Ejecutar con `node web-promotion-package/check-integration-layout.mjs`.
- Las páginas de referencia se esperan en una raíz de hosting con las rutas `/admin` y `/cliente`.
- Si el HTML se publica en la raíz, las dependencias `./web-promotion-package/*.js` deben existir en `web-promotion-package/` bajo esa misma raíz.
- Esta comprobación no llama a Supabase, no crea registros y no prueba credenciales/RPC remotas.
- No sustituye E2E de navegador ni certifica el deployment real de Vercel.
