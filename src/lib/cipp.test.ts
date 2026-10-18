import { describe, expect, it } from 'vitest'
import { combineCippDimensions, satisfactionRates, summarizeCippCounts } from './cipp'

describe('CIPP calculations from observed response counts', () => {
  it('calculates a weighted mean, percent of full score, and sample SD', () => {
    const result = summarizeCippCounts([0, 0, 0, 1, 1])
    expect(result.responses).toBe(2)
    expect(result.mean).toBe(4.5)
    expect(result.percentOfFullScore).toBe(90)
    expect(result.sampleSd).toBeCloseTo(Math.SQRT1_2)
    expect(result.passed).toBe(true)
  })

  it('keeps empty dimensions unscored and requires all four to summarize a project', () => {
    const missing = summarizeCippCounts([0, 0, 0, 0, 0])
    expect(missing.mean).toBeNull()
    expect(missing.sampleSd).toBeNull()
    expect(combineCippDimensions([summarizeCippCounts([0, 0, 0, 0, 1]), missing, missing, missing]).complete).toBe(false)
  })

  it('separates percent satisfied from percent of maximum score', () => {
    const result = satisfactionRates({ satisfied: 8, respondents: 10, scoreTotal: 47.76, maxScore: 5 })
    expect(result.satisfiedPercent).toBe(80)
    expect(result.scorePercentOfFull).toBeCloseTo(95.52)
  })

  it('rejects negative response counts', () => {
    expect(() => summarizeCippCounts([0, 0, -1, 0, 0])).toThrow()
  })
})
