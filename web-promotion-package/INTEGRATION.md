# Integración del paquete

Estado: separado, no conectado a páginas productivas.

## Montaje en Admin (después de validar la sesión)
El HTML actual de Admin guarda el token de la sesión de administrador en `barber_admin_token` y define una función RPC que envía `p_token`. En la fuente web original, importa `mountPromotionsAdmin` desde `admin-promotions.js` y móntalo en un contenedor nuevo dentro de la app autenticada. Usa el mismo adaptador RPC actual, no agregues otra autenticación. Desmontar el componente al cerrar sesión. No se debe inyectar antes del login.

## Utilidades de Cliente
`customer-promotion-utils.js` espera filas ya devueltas por la función pública de promociones y un ID de servicio. La vista Cliente actual usa IDs numéricos del 1 al 9. El paquete todavía no adapta la reserva ni cambia su llamada existente. Antes de conectarlo:
- Definir cómo se relacionan esos IDs numéricos con IDs UUID en catálogo, o mantener una clave externa única para cada servicio.
- Obtener promociones válidas para la fecha y hora seleccionadas por el cliente.
- Usar el precio calculado en el resumen y el mismo importe de forma atómica en la creación de la reserva; jamás confiar en precio enviado por el navegador.
- Guardar el precio acordado en la reserva al crearse. No recalcular reservas históricas o confirmadas si cambia una promoción o servicio.

## Bloqueo de UI detectado
El adaptador Admin llama a RPC descritas en los borradores SQL. Todavía no debe conectarse a ningún Supabase hasta que las migraciones se prueben en un proyecto aislado. Las funciones del borrador actual no son suficientes para declarar terminado el flujo de promociones ni la tarea programada.
