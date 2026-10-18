import { describe, expect, it } from 'vitest'
import { calculateLineTotalCents, formatCents, sumLineTotalsCents } from './money'

describe('project line amount arithmetic', () => {
  it('multiplies amount fields and rounds per line to cents', () => {
    expect(formatCents(calculateLineTotalCents('3', '12.50'))).toBe('37.50')
    expect(formatCents(calculateLineTotalCents('0.333', '10.00'))).toBe('3.33')
  })
  it('sums cents without floating-point accumulation', () => {
    expect(formatCents(sumLineTotalsCents([{quantity:'0.1',unitPrice:'0.10'},{quantity:'0.2',unitPrice:'0.10'}]))).toBe('0.03')
  })
  it('rejects negative or non-numeric values', () => {
    expect(() => calculateLineTotalCents('-1', '10')).toThrow()
    expect(() => calculateLineTotalCents('1', 'abc')).toThrow()
  })
})
