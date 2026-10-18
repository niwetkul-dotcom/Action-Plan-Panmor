export type ScoreCounts = [number, number, number, number, number]
export type CippDimensionResult = {
  responses: number
  mean: number | null
  percentOfFullScore: number | null
  sampleSd: number | null
  level: string | null
  passed: boolean | null
}

export function summarizeCippCounts(counts: ScoreCounts, target = 4): CippDimensionResult {
  if (counts.some(value => !Number.isInteger(value) || value < 0)) throw new Error('จำนวนคำตอบต้องเป็นจำนวนเต็มที่ไม่ติดลบ')
  const responses = counts.reduce((sum, value) => sum + value, 0)
  if (!responses) return { responses: 0, mean: null, percentOfFullScore: null, sampleSd: null, level: null, passed: null }
  const scoreTotal = counts.reduce((sum, count, index) => sum + count * (index + 1), 0)
  const squareTotal = counts.reduce((sum, count, index) => sum + count * (index + 1) ** 2, 0)
  const mean = scoreTotal / responses
  const variance = responses < 2 ? null : Math.max(0, (squareTotal - scoreTotal ** 2 / responses) / (responses - 1))
  const rounded = Math.round(mean * 100) / 100
  const level = rounded >= 4.51 ? 'มากที่สุด' : rounded >= 3.51 ? 'มาก' : rounded >= 2.51 ? 'ปานกลาง' : rounded >= 1.51 ? 'น้อย' : 'น้อยที่สุด'
  return { responses, mean, percentOfFullScore: mean / 5 * 100, sampleSd: variance === null ? null : Math.sqrt(variance), level, passed: mean >= target }
}

export function combineCippDimensions(results: CippDimensionResult[]) {
  const available = results.filter((result): result is CippDimensionResult & { mean: number; percentOfFullScore: number } => result.mean !== null && result.percentOfFullScore !== null)
  if (available.length !== 4) return { complete: false, mean: null as number | null, percentOfFullScore: null as number | null, completedDimensions: available.length }
  const mean = available.reduce((sum, result) => sum + result.mean, 0) / 4
  return { complete: true, mean, percentOfFullScore: mean / 5 * 100, completedDimensions: 4 }
}

export function satisfactionRates(args: { satisfied: number; respondents: number; scoreTotal?: number; maxScore?: number }) {
  const { satisfied, respondents, scoreTotal, maxScore } = args
  if (![satisfied, respondents].every(Number.isInteger) || respondents < 0 || satisfied < 0 || satisfied > respondents) throw new Error('จำนวนผู้ตอบหรือจำนวนผู้พึงพอใจไม่ถูกต้อง')
  if (respondents === 0) return { satisfiedPercent: null, scorePercentOfFull: null }
  if (scoreTotal === undefined || maxScore === undefined) return { satisfiedPercent: satisfied / respondents * 100, scorePercentOfFull: null }
  if (!(maxScore > 0) || scoreTotal < 0 || scoreTotal > respondents * maxScore) throw new Error('คะแนนหรือคะแนนเต็มไม่ถูกต้อง')
  return { satisfiedPercent: satisfied / respondents * 100, scorePercentOfFull: scoreTotal / (respondents * maxScore) * 100 }
}
