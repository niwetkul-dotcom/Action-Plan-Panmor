import { useRef, useState } from 'react'
import { Eraser } from 'lucide-react'
export function SignaturePad({ onChange }: { onChange:(signature:string|null)=>void }) {
  const canvasRef=useRef<HTMLCanvasElement>(null), drawing=useRef(false), [hasInk,setHasInk]=useState(false)
  function point(e:React.PointerEvent<HTMLCanvasElement>){const canvas=canvasRef.current!,rect=canvas.getBoundingClientRect();return{x:(e.clientX-rect.left)*canvas.width/rect.width,y:(e.clientY-rect.top)*canvas.height/rect.height}}
  function start(e:React.PointerEvent<HTMLCanvasElement>){const canvas=canvasRef.current!,ctx=canvas.getContext('2d');if(!ctx)return;canvas.setPointerCapture(e.pointerId);const p=point(e);ctx.beginPath();ctx.moveTo(p.x,p.y);ctx.lineWidth=3;ctx.lineCap='round';ctx.lineJoin='round';ctx.strokeStyle='#2d2a3a';drawing.current=true}
  function move(e:React.PointerEvent<HTMLCanvasElement>){if(!drawing.current)return;const ctx=canvasRef.current?.getContext('2d');if(!ctx)return;const p=point(e);ctx.lineTo(p.x,p.y);ctx.stroke();setHasInk(true)}
  function finish(){if(!drawing.current)return;drawing.current=false;const canvas=canvasRef.current;if(canvas)onChange(canvas.toDataURL('image/png'))}
  function clear(){const canvas=canvasRef.current;if(!canvas)return;canvas.getContext('2d')?.clearRect(0,0,canvas.width,canvas.height);setHasInk(false);onChange(null)}
  return <div className="signature-wrap"><div className="signature-label"><span>ลงลายมือชื่อผู้พิจารณา</span><button type="button" className="link-button" onClick={clear} disabled={!hasInk}><Eraser size={14}/> ล้างลายเซ็น</button></div><canvas ref={canvasRef} className="signature-canvas" width={900} height={250} onPointerDown={start} onPointerMove={move} onPointerUp={finish} onPointerCancel={finish} aria-label="พื้นที่ลงลายมือชื่อ"/><small>วาดด้วยเมาส์หรือสัมผัสบนหน้าจอ</small></div>
}
