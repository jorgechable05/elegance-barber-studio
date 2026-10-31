/**
 * Utilidades de precios/promociones de cliente.
 *
 * Paquete de integración, NO desplegar hasta conectarlo y probarlo con el sitio real.
 * Día de semana usa JS: domingo=0...sábado=6.
 */
export function isPromotionApplicable(promotion, serviceId, appointmentDateTime) {
  if (!promotion || promotion.status && promotion.status !== "approved") return false;
  const when = new Date(appointmentDateTime);
  const starts = new Date(promotion.starts_at);
  const ends = new Date(promotion.ends_at);
  if (![when, starts, ends].every(d => Number.isFinite(d.getTime()))) return false;
  if (when < starts || when >= ends) return false;

  const allowedServices = (promotion.service_ids || []).map(String);
  if (!allowedServices.includes(String(serviceId))) return false;

  const zonedParts = new Intl.DateTimeFormat("en-US", { timeZone: "America/Merida", weekday: "short", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).formatToParts(when);
  const parts = Object.fromEntries(zonedParts.map(part => [part.type, part.value]));
  const weekdayMap = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };
  const weekday = weekdayMap[parts.weekday];
  if (Array.isArray(promotion.weekdays) && promotion.weekdays.length &&
      !promotion.weekdays.map(Number).includes(weekday)) return false;

  // SQL TIME expected as HH:MM[:SS]. For now, overnight windows are rejected.
  if (promotion.start_time || promotion.end_time) {
    if (!promotion.start_time || !promotion.end_time) return false;
    const start = parseMinutes(promotion.start_time);
    const end = parseMinutes(promotion.end_time);
    const current = Number(parts.hour) * 60 + Number(parts.minute);
    if (start == null || end == null || end <= start) return false;
    if (current < start || current >= end) return false;
  }
  if (Number.isFinite(Number(promotion.max_uses)) && promotion.max_uses != null &&
      Number(promotion.uses_count || 0) >= Number(promotion.max_uses)) return false;
  return true;
}

function parseMinutes(value) {
  const match = /^(\d{2}):(\d{2})(?::\d{2})?$/.exec(String(value));
  if (!match) return null;
  const h = Number(match[1]), m = Number(match[2]);
  if (h > 23 || m > 59) return null;
  return h * 60 + m;
}

/**
 * Always calculate from the base catalog price. Returns exact cents.
 * Caller must persist the agreed appointment price at booking time; it must never
 * recalculate already-confirmed reservations from a changed catalog/promotion.
 */
export function calculatePromotionPrice(basePrice, promotion) {
  const base = Number(basePrice);
  const value = Number(promotion?.discount_value);
  if (!Number.isFinite(base) || base < 0 ||
      !Number.isFinite(value) || value <= 0) throw new TypeError("Precio o descuento inválido");

  let result;
  if (promotion.discount_type === "percent") {
    if (value > 100) throw new RangeError("El porcentaje no puede superar 100");
    result = base * (1 - value / 100);
  } else if (promotion.discount_type === "fixed_price") {
    if (value > base) throw new RangeError("El precio especial no debe superar el precio normal");
    result = value;
  } else {
    throw new TypeError("Tipo de promoción desconocido");
  }
  return Math.round((result + Number.EPSILON) * 100) / 100;
}

export function applicablePromotions(promotions, serviceId, appointmentDateTime) {
  return (promotions || []).filter(p =>
    isPromotionApplicable(p, serviceId, appointmentDateTime)
  );
}
