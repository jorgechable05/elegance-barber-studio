# Estado de implementación (actualizado 2026-10-31)

- [x] Módulo Admin aislado para administrar servicios y promociones, con aprobación/rechazo/pausa.
- [x] Utilidades de cliente para filtrar promociones por servicio, vigencia, día y hora local del negocio (America/Merida).
- [x] Pruebas de elegibilidad, estado pendiente, límites porcentuales, precio especial y horario inválido.
- [x] Pruebas locales del paquete: 10/10 con Node.js bajo TZ=America/Merida; comprobación sintáctica de módulos JavaScript exitosa.
- [ ] Integración con las páginas existentes (bloqueada: este repositorio contiene wrapper Android, pero no la fuente web versionada de /admin, /cliente ni /pos).
- [ ] Validar borradores SQL en Supabase no productivo y cerrar equivalencia de IDs numéricos 1–9 con el catálogo.
- [ ] Calcular y persistir el precio de reserva desde el backend al crear cita; no confiar en el precio del navegador.
- [ ] Mostrar promociones aplicables en los clientes de reserva sin recalcular reservas existentes.
- [ ] Ejecutar regresión histórica Admin/Cliente/POS y pruebas de extremo a extremo.
- [ ] Validar generación automática programada y seguridad de una función interna.
- [ ] Vista previa aislada y revisión manual.

**No desplegar a producción.** No se aplicaron migraciones a Supabase; no se cambió Vercel ni se modificó POS.
