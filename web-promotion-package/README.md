# Paquete aislado de integración — Servicios y promociones

> **NO DESPLEGAR A PRODUCCIÓN.** Este paquete está preparado para revisar e integrar al sitio web real cuando se obtenga su fuente versionada. No sustituye las páginas `/admin`, `/cliente` ni `/pos`.

## Contenido propuesto
- `admin-promotions.js`: módulo JS adaptable para añadir una sección separada a la vista Admin después de validar sesión.
- `customer-promotion-utils.js`: filtros y cálculo de promociones para fecha/hora futura seleccionada.
- `tests/promotion-utils.test.mjs`: pruebas unitarias sin acceso a Supabase.

## Contratos no negociables
- Los identificadores actuales de servicio del cliente son numéricos (1–9); no cambiar `barber_create_reservation` por UUID sin una migración de compatibilidad.
- El módulo de promociones no modifica ventas ni las RPC POS.
- Solo promociones aprobadas, dentro de vigencia, día, horario y servicio se deben mostrar.
- El precio de una reserva ya creada no se recalcula si cambia el catálogo.
- Las sugerencias diarias siempre se mantienen en revisión pendiente hasta decisión administrativa.
