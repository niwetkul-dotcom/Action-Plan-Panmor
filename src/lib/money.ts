const decimalScale = (value: string | number, digits: number): bigint => {
  const input = String(value).trim()
  if (!/^\d+(?:\.\d+)?$/.test(input)) throw new Error('จำนวนเงินต้องเป็นเลขไม่ติดลบ')
  const [whole, fraction = ''] = input.split('.')
  const factor = 10n ** BigInt(digits)
  const kept = fraction.slice(0, digits).padEnd(digits, '0')
  const result = BigInt(whole) * factor + BigInt(kept || '0')
  if (fraction.length > digits && Number(fraction[digits]) >= 5) return result + 1n
  return result
}

/** Returns cents, using thousandth precision for quantity and half-up rounding per line. */
export function calculateLineTotalCents(quantity: string | number, unitPrice: string | number): bigint {
  const quantityMilli = decimalScale(quantity, 3)
  const priceCents = decimalScale(unitPrice, 2)
  const product = quantityMilli * priceCents
  const cents = product / 1000n
  const remainder = product % 1000n
  return cents + (remainder >= 500n ? 1n : 0n)
}

export function formatCents(cents: bigint): string {
  const whole = cents / 100n
  const fraction = (cents % 100n).toString().padStart(2, '0')
  return `${whole}.${fraction}`
}

export function sumLineTotalsCents(items: Array<{ quantity: string | number; unitPrice: string | number }>): bigint {
  return items.reduce((sum, item) => sum + calculateLineTotalCents(item.quantity, item.unitPrice), 0n)
}
