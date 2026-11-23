import {chartPointKey,selectionIndex} from './chartSelection.js'
import { useEffect, useRef, useState } from 'react'
const labels = { agachamento: 'Agachamento', supino: 'Supino', terra: 'Terra', total: 'Total SBD', volume: 'Volume semanal', peso: 'Peso corporal', dots: 'DOTS' }
const number = (value, digits = 1) => value == null ? '—' : new Intl.NumberFormat('pt-BR', { maximumFractionDigits: digits }).format(value)
const date = (value) => new Date(`${value}T12:00:00`)
const dayLabel = (value) => date(value).toLocaleDateString('pt-BR')
const weightOrigins = { onboarding:'Cadastro inicial', treino:'Treino', descanso:'Descanso', manual:'Atualização do aluno', treinador:'Ajuste do treinador', legado:'Registro anterior' }

export default function ProgressChart({ points, metric, referencePr, target = null, trend = false, onSelect }) {
  const [selection,setSelection]=useState(null)
  const selectedIndex=selectionIndex(points,metric,selection)
  const selected=selectedIndex<0?null:selectedIndex
  const pinned=useRef(false),closeTimer=useRef(null)
  const cancelClose=()=>{if(closeTimer.current)clearTimeout(closeTimer.current);closeTimer.current=null}
  function setSelected(index){cancelClose();setSelection(index==null?null:{metric,key:chartPointKey(points[index])})}
  function close(){cancelClose();pinned.current=false;setSelection(null)}
  function delayClose(){if(!pinned.current){cancelClose();closeTimer.current=setTimeout(close,180)}}
  function selectPinned(index){pinned.current=true;setSelected(index)}
  const [width, setWidth] = useState(900)
  const container = useRef(null)
  const pointer = useRef(null)
  const tooltipId = `progress-tooltip-${metric}`
  useEffect(()=>{if(selection && selectionIndex(points,metric,selection)<0)close()},[points,metric,selection])
  useEffect(()=>()=>cancelClose(),[])
  useEffect(() => {
    const observer = new ResizeObserver(([entry]) => setWidth(Math.max(280, entry.contentRect.width)))
    if (container.current) observer.observe(container.current)
    const dismiss = (event) => { if (!container.current?.contains(event.target)) close() }
    document.addEventListener('pointerdown', dismiss)
    return () => { observer.disconnect(); document.removeEventListener('pointerdown', dismiss) }
  }, [])
  const height = 300, left = 48, right = 18, top = 24, bottom = 45
  const values = [...points.map((point) => point.valor), ...(target != null ? [target] : [])]
  const smooth = points.map((point, index) => ({ ...point, valor: points.slice(Math.max(0, index - 6), index + 1).reduce((sum, entry) => sum + entry.valor, 0) / Math.min(index + 1, 7) }))
  const minimum = values.length ? Math.min(...values) : 0
  const maximum = values.length ? Math.max(...values) : 1
  const padding = Math.max((maximum - minimum) * .18, maximum * (metric === 'peso' ? .005 : .06), metric === 'peso' ? .2 : 1)
  const lo = Math.max(0, minimum - padding), hi = maximum + padding
  const start = points.length ? date(points[0].data).getTime() : 0
  const end = points.length ? date(points[points.length - 1].data).getTime() : 1
  const x = (point) => start === end ? (width + left - right) / 2 : left + (date(point.data).getTime() - start) / (end - start) * (width - left - right)
  const y = (point) => top + (hi - point.valor) / (hi - lo) * (height - top - bottom)
  const tickCount = Math.max(2, Math.min(8, Math.floor((width - left - right) / 88) + 1))
  const ticks = start === end ? [start] : Array.from({ length: tickCount }, (_, index) => start + (end - start) * index / (tickCount - 1))
  const unit = metric === 'dots' ? 'pts' : 'kg'
  const point = selected != null ? points[selected] : null
  const lift = ['agachamento', 'supino', 'terra'].includes(metric)
  const prFor = (entry) => entry?.prMovimento ?? referencePr
  const percentageFor = (entry) => entry?.percentualPr ?? (prFor(entry) > 0 ? entry.valor / prFor(entry) * 100 : null)
  return <div className="athlete-chart" ref={container} onKeyDown={(event) => { if (event.key === 'Escape') close() }}>
    {!points.length ? <div className="athlete-empty"><span className="empty-chart-icon">↗</span><h3>O próximo recorde começa aqui.</h3><p>Nenhum registro de {labels[metric].toLowerCase()} neste período.</p></div> : <>
      <div className="chart-plot">
        <svg viewBox={`0 0 ${width} ${height}`} onPointerDownCapture={event=>{pointer.current={type:event.pointerType,x:event.clientX,y:event.clientY}}}
          onClick={event=>{
            const down=pointer.current
            if(!down || down.type!=='touch' || Math.hypot(event.clientX-down.x,event.clientY-down.y)>12)return
            const svg=event.currentTarget, matrix=svg.getScreenCTM()
            if(!matrix)return
            const position=svg.createSVGPoint();position.x=event.clientX;position.y=event.clientY
            const local=position.matrixTransform(matrix.inverse())
            if(local.x<left-15 || local.x>width-right+15 || local.y<top-15 || local.y>height-bottom+15)return
            let nearest=0, distance=Infinity
            points.forEach((entry,index)=>{const d=Math.hypot(x(entry)-local.x,y(entry)-local.y);if(d<distance){distance=d;nearest=index}})
            selectPinned(nearest);onSelect?.(points[nearest])
          }} role="group" aria-label={`Evolução de ${labels[metric]}. Selecione um ponto para ver os detalhes.`}>
          {[0, 1, 2, 3, 4].map((index) => { const value = lo + (hi - lo) * index / 4; const lineY = top + (4 - index) / 4 * (height - top - bottom); return <g key={index}><line x1={left} y1={lineY} x2={width - right} y2={lineY} className="chart-grid" /><text x={left - 10} y={lineY + 4} textAnchor="end">{number(value, metric === 'peso' ? 1 : 0)}</text></g> })}
          {ticks.map((tick, index) => { const tickX = start === end ? (width + left - right) / 2 : left + (tick - start) / (end - start) * (width - left - right); return <g key={tick}><line x1={tickX} y1={height - bottom} x2={tickX} y2={height - bottom + 5} className="chart-grid" /><text x={tickX} y={height - 18} textAnchor={ticks.length === 1 ? 'middle' : index === 0 ? 'start' : index === ticks.length - 1 ? 'end' : 'middle'}>{new Date(tick).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', ...(width > 700 ? { year: '2-digit' } : {}) })}</text></g> })}
          {target != null && <g className="chart-target"><line x1={left} y1={y({valor:target})} x2={width-right} y2={y({valor:target})} /><text x={width-right} y={y({valor:target})-7} textAnchor="end">Meta: {number(target)} kg</text></g>}
          {trend && points.length>1 && <polyline points={smooth.map((entry)=>`${x(entry)},${y(entry)}`).join(' ')} fill="none" className="chart-trend" />}
          <polyline points={points.map((entry) => `${x(entry)},${y(entry)}`).join(' ')} fill="none" className="chart-line" />
          {point && <line x1={x(point)} y1={top} x2={x(point)} y2={height - bottom} className="chart-crosshair" />}
          {points.map((entry, index) => <g key={`${entry.data}-${index}`} className="chart-point" tabIndex="0" role="button" aria-describedby={selected === index ? tooltipId : undefined} aria-label={`${dayLabel(entry.data)}, ${number(entry.valor, metric === 'peso' ? 2 : 1)} ${unit}${entry.repeticoes ? `, ${entry.repeticoes} repetições, RPE ${entry.rpe ?? 'não informado'}` : ''}${percentageFor(entry) != null ? `, ${number(percentageFor(entry))}% do PR` : ''}`} onPointerEnter={(event) => { if (event.pointerType !== 'touch' && !pinned.current) {cancelClose();setSelected(index)} }} onPointerLeave={(event) => { if (event.pointerType !== 'touch') delayClose() }} onFocus={()=>{cancelClose();setSelected(index)}} onBlur={(event) => { if(!container.current?.contains(event.relatedTarget))close() }} onClick={(event) => { if(pointer.current?.type==='touch')return; selectPinned(index); onSelect?.(entry) }} onKeyDown={(event) => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); selectPinned(index); onSelect?.(entry) } }}>
            <circle cx={x(entry)} cy={y(entry)} r="22" className="chart-hit-area" />
            <circle cx={x(entry)} cy={y(entry)} r={selected === index ? 7 : 4.5} className="chart-dot" />
          </g>)}
        </svg>
        {point && <div id={tooltipId} role="group" aria-label="Detalhes do registro" onPointerEnter={cancelClose} onPointerLeave={delayClose} onFocusCapture={cancelClose} onBlurCapture={event=>{if(!container.current?.contains(event.relatedTarget))close()}} className="chart-floating-tooltip" style={{ left: Math.max(6, Math.min(width - 238, x(point) - 112)), top: y(point) < 150 ? y(point) + 18 : Math.max(6, y(point) - (lift ? 178 : metric === 'peso' ? 150 : 90)) }}>
          <div className="chart-detail-heading"><strong>{dayLabel(point.data)}</strong><button type="button" aria-label="Fechar detalhe do gráfico" onClick={close}>✕</button></div><dl><div><dt>{lift ? 'Carga feita' : labels[metric]}</dt><dd>{number(point.valor, metric === 'peso' ? 2 : 1)} {unit}</dd></div>{lift && <><div><dt>Repetições</dt><dd>{point.repeticoes ?? 'Não informado'}</dd></div><div><dt>RPE real</dt><dd>{point.rpe == null ? 'Não informado' : number(point.rpe)}</dd></div><div className="tooltip-pr"><dt>% do PR</dt><dd>{percentageFor(point) == null ? '—' : `${number(percentageFor(point))}%`}</dd></div></>}{metric==='peso' && <><div><dt>Variação anterior</dt><dd>{point.variacaoAnterior == null ? '—' : `${point.variacaoAnterior>0?'+':''}${number(point.variacaoAnterior,2)} kg`}</dd></div><div><dt>Origem</dt><dd>{weightOrigins[point.origem] || 'Registro anterior'}</dd></div></>}</dl>{lift && <small>PR: {number(prFor(point))} kg · maior carga de todo o histórico</small>}
          <div className="chart-record-navigation" role="group" aria-label="Navegar pelos registros"><button type="button" disabled={selected===0} onClick={()=>selectPinned(Math.max(0,selected-1))}>← Anterior</button><span>{selected+1} de {points.length}</span><button type="button" disabled={selected===points.length-1} onClick={()=>selectPinned(Math.min(points.length-1,selected+1))}>Próximo →</button></div>
        </div>}
      </div>
    </>}
  </div>
}

