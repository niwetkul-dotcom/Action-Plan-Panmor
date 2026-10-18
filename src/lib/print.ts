export async function printWhenReady(root: Document = document) {
  if (root.fonts?.ready) await root.fonts.ready
  const images = Array.from(root.querySelectorAll<HTMLImageElement>('.print-sheet img'))
  const failures: string[] = []
  await Promise.all(images.map(async image => {
    if (!image.complete) await new Promise<void>(resolve => {
      image.addEventListener('load', () => resolve(), { once: true })
      image.addEventListener('error', () => resolve(), { once: true })
    })
    if (image.naturalWidth === 0) failures.push(image.alt || image.currentSrc || image.src || 'ภาพที่ไม่ทราบชื่อ')
    else if (typeof image.decode === 'function') await image.decode().catch(() => failures.push(image.alt || image.currentSrc || image.src))
  }))
  if (failures.length) throw new Error(`โหลดภาพสำหรับพิมพ์ไม่ครบ: ${[...new Set(failures)].join(', ')}`)
  window.print()
}
