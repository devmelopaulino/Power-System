import { useMemo, useState } from 'react'

const normalize=(text)=>String(text||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase()
const dateLabel=(day)=>new Date(day+'T12:00:00').toLocaleDateString('pt-BR')
const PAGE_SIZE=8

export default function RecentRecordPicker({ records, label, placeholder, onSelect, disabled=false }) {
  const [query,setQuery]=useState(''),[page,setPage]=useState(0)
  const filtered=useMemo(()=>{
    const words=normalize(query).trim().split(/\s+/).filter(Boolean)
    return [...records].sort((a,b)=>b.date.localeCompare(a.date)||Number(b.id)-Number(a.id)).filter(record=>{
      const haystack=normalize([record.date,dateLabel(record.date),record.title,record.subtitle,record.search].join(' '))
      return words.every(word=>haystack.includes(word))
    })
  },[records,query])
  const lastPage=Math.max(0,Math.ceil(filtered.length/PAGE_SIZE)-1)
  const currentPage=Math.min(page,lastPage)
  const shown=filtered.slice(currentPage*PAGE_SIZE,(currentPage+1)*PAGE_SIZE)
  return <section className="recent-record-picker" aria-label={label}>
    <label>{label}<input type="search" placeholder={placeholder} value={query} onKeyDown={event=>{if(event.key==='Enter')event.preventDefault()}} onChange={event=>{setQuery(event.target.value);setPage(0)}} /></label>
    <p className="recent-record-count" role="status">{filtered.length?`${currentPage*PAGE_SIZE+1}–${currentPage*PAGE_SIZE+shown.length} de ${filtered.length} registros · mais recentes primeiro`:'Nenhum registro encontrado.'}</p>
    <ul>{shown.map(record=><li key={record.id}><button type="button" disabled={disabled} onClick={()=>onSelect(record)}><span className="recent-record-date">{dateLabel(record.date)}</span><span><strong>{record.title}</strong>{record.subtitle&&<small>{record.subtitle}</small>}</span><span aria-hidden="true">↗</span></button></li>)}</ul>
    {filtered.length>PAGE_SIZE&&<div className="recent-record-pages"><button className="athlete-button" type="button" disabled={currentPage===0} onClick={()=>setPage(currentPage-1)}>Anteriores</button><span>Página {currentPage+1} de {lastPage+1}</span><button className="athlete-button" type="button" disabled={currentPage===lastPage} onClick={()=>setPage(currentPage+1)}>Próximos</button></div>}
  </section>
}
