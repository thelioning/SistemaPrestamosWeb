import{useEffect,useMemo,useState}from'react'
import'./ClienteDetalleView.css'

const API=import.meta.env.VITE_API_URL??'http://localhost:5159'
type Prestamo={prestamoId:number;clienteId:number;cliente:string;tipo:string;estado:string;montoPrestado:number;pagado:number;balance:number;vencido:number;diasAtraso:number;frecuencia:string;montoRedito?:number;fechaInicio:string;ultimoPago?:string}
type Movimiento={id:number;prestamoId:number;fecha:string;concepto:string;monto:number;estado:string;recibo?:string;observacion?:string}
type Historial={id:number;prestamoId:number;fecha:string;accion:string;descripcion?:string}
type EstadoCuenta={cliente:{id:number;nombre:string;documento?:string;telefono?:string;direccion?:string};totalPrestado:number;totalPagado:number;balance:number;prestamos:Prestamo[];movimientos:Movimiento[];historial:Historial[]}
type Recibo={id:number;pagoId:number;numero:string;prestamoId:number;tipoPago:string;fecha:string;monto:number;estado:string;motivoAnulacion?:string;puedeAnular:boolean;rutaPdf?:string}
const money=(v=0)=>new Intl.NumberFormat('es-DO',{style:'currency',currency:'DOP'}).format(v)
const date=(v:string)=>new Intl.DateTimeFormat('es-DO',{dateStyle:'medium'}).format(new Date(v.includes('T')?v:`${v}T00:00:00`))
async function req(path:string,token:string){const r=await fetch(`${API}${path}`,{headers:{Authorization:`Bearer ${token}`}});if(!r.ok)throw new Error('No fue posible cargar la ficha del cliente.');return r.json()}

export default function ClienteDetalleView({token,clienteId,onBack}:{token:string;clienteId:number;onBack:()=>void}){
 const[data,setData]=useState<EstadoCuenta|null>(null)
 const[recibos,setRecibos]=useState<Recibo[]>([])
 const[tab,setTab]=useState<'resumen'|'prestamos'|'pagos'|'recibos'|'historial'>('resumen')
 const[error,setError]=useState('')
 const[opening,setOpening]=useState('')

 useEffect(()=>{
  setError('')
  Promise.all([
   req(`/api/reportes/clientes/${clienteId}/estado-cuenta`,token),
   req(`/api/recibos/clientes/${clienteId}`,token)
  ]).then(([d,r])=>{setData(d);setRecibos(r)}).catch(e=>setError(e.message))
 },[clienteId,token])

 const metrics=useMemo(()=>{
  const loans=data?.prestamos??[]
  const reditos=loans.filter(x=>x.tipo==='REDITO')
  const ultimoPagoRedito=reditos.map(x=>x.ultimoPago).filter((x):x is string=>Boolean(x)).sort().at(-1)
  return{
   total:loans.length,
   activos:loans.filter(x=>x.estado==='ACTIVO').length,
   saldados:loans.filter(x=>x.estado==='SALDADO').length,
   atrasados:loans.filter(x=>x.estado==='ATRASADO'||x.vencido>0).length,
   vencido:loans.reduce((a,x)=>a+x.vencido,0),
   mayorAtraso:loans.reduce((a,x)=>Math.max(a,x.diasAtraso),0),
   capitalRedito:reditos.reduce((a,x)=>a+x.balance,0),
   reditoPagado:data?.movimientos.filter(x=>x.estado==='APLICADO'&&x.concepto==='REDITO').reduce((a,x)=>a+x.monto,0)??0,
   ultimoPagoRedito
  }
 },[data])

 async function openPdf(path:string,key:string){
  setOpening(key);setError('')
  try{
   const r=await fetch(`${API}${path}`,{headers:{Authorization:`Bearer ${token}`}})
   if(!r.ok)throw new Error('No fue posible abrir el PDF.')
   const url=URL.createObjectURL(await r.blob())
   window.open(url,'_blank','noopener,noreferrer')
   setTimeout(()=>URL.revokeObjectURL(url),120000)
  }catch(e){setError((e as Error).message)}
  finally{setOpening('')}
 }

 if(error&&!data)return <section className="client-detail-page"><button className="detail-back" onClick={onBack}>← Volver a clientes</button><div className="inline-error">{error}</div></section>
 if(!data)return <section className="client-detail-page"><p>Cargando ficha del cliente…</p></section>

 const initials=data.cliente.nombre.split(' ').slice(0,2).map(x=>x[0]).join('').toUpperCase()

 return <section className="client-detail-page">
  <div className="client-detail-top">
   <button className="detail-back" onClick={onBack}>← Volver a clientes</button>
   <button className="detail-pdf" onClick={()=>openPdf(`/api/reportes/clientes/${clienteId}/estado-cuenta/pdf`,'estado')} disabled={opening==='estado'}>
    {opening==='estado'?'Generando…':'Estado de cuenta PDF'}
   </button>
  </div>

  {error&&<div className="inline-error">{error}<button onClick={()=>setError('')}>×</button></div>}

  <section className="client-profile-card">
   <div className="client-profile-main">
    <span className="client-profile-avatar">{initials}</span>
    <div>
     <p className="eyebrow">FICHA DEL CLIENTE</p>
     <h2>{data.cliente.nombre}</h2>
     <div className="client-contact">
      <span>{data.cliente.documento||'Documento no registrado'}</span>
      <span>{data.cliente.telefono||'Teléfono no registrado'}</span>
     </div>
    </div>
   </div>
   <div className="client-address"><small>Dirección</small><b>{data.cliente.direccion||'No registrada'}</b></div>
  </section>

  <section className="client-kpis">
   <article><span>Total prestado</span><strong>{money(data.totalPrestado)}</strong></article>
   <article><span>Total pagado</span><strong>{money(data.totalPagado)}</strong></article>
   <article><span>Saldo actual</span><strong>{money(data.balance)}</strong></article>
   <article className={metrics.vencido>0?'client-alert':''}><span>Total vencido</span><strong>{money(metrics.vencido)}</strong></article>
  </section>

  <section className="client-credit-summary">
   <div><b>{metrics.total}</b><span>Préstamos</span></div>
   <div><b>{metrics.activos}</b><span>Activos</span></div>
   <div><b>{metrics.saldados}</b><span>Saldados</span></div>
   <div className={metrics.atrasados>0?'client-alert-box':''}><b>{metrics.atrasados}</b><span>Con atraso</span></div>
   <div><b>{metrics.mayorAtraso}</b><span>Mayor atraso (días)</span></div>
  </section>

  <div className="client-tabs">
   {(['resumen','prestamos','pagos','recibos','historial'] as const).map(x=>
    <button key={x} className={tab===x?'selected':''} onClick={()=>setTab(x)}>
     {x==='resumen'?'Resumen':x==='prestamos'?'Préstamos':x==='pagos'?'Pagos':x==='recibos'?'Recibos':'Historial'}
    </button>
   )}
  </div>

  {tab==='resumen'&&<section className="client-detail-grid">
   <article className="client-detail-card">
    <span>COMPORTAMIENTO ACTUAL</span><h3>Resumen de cartera</h3>
    <dl>
     <div><dt>Préstamos totales</dt><dd>{metrics.total}</dd></div>
     <div><dt>Préstamos activos</dt><dd>{metrics.activos}</dd></div>
     <div><dt>Préstamos saldados</dt><dd>{metrics.saldados}</dd></div>
     <div><dt>Préstamos con atraso</dt><dd>{metrics.atrasados}</dd></div>
     <div><dt>Saldo vencido</dt><dd>{money(metrics.vencido)}</dd></div>
     <div><dt>Mayor atraso</dt><dd>{metrics.mayorAtraso} días</dd></div>
     {metrics.capitalRedito>0&&<><div><dt>Capital pendiente Rédito</dt><dd>{money(metrics.capitalRedito)}</dd></div><div><dt>Réditos pagados</dt><dd>{money(metrics.reditoPagado)}</dd></div><div><dt>Último pago Rédito</dt><dd>{metrics.ultimoPagoRedito?date(metrics.ultimoPagoRedito):'Sin pagos'}</dd></div></>}
    </dl>
   </article>
   <article className="client-detail-card">
    <span>ACTIVIDAD RECIENTE</span><h3>Últimos movimientos</h3>
    {data.movimientos.length?<div className="recent-list">{data.movimientos.slice(0,5).map(m=>
     <div key={m.id}><span><b>{m.concepto}</b><small>PR-{String(m.prestamoId).padStart(5,'0')} · {date(m.fecha)}</small></span><strong>{money(m.monto)}</strong></div>
    )}</div>:<p className="empty-detail">Este cliente todavía no tiene pagos registrados.</p>}
   </article>
  </section>}

  {tab==='prestamos'&&<section className="client-table-card">
   <div className="client-section-head"><div><span>PRÉSTAMOS</span><h3>{data.prestamos.length} registros</h3></div></div>
   <div className="table-wrap"><table className="client-detail-table"><thead><tr><th>Préstamo</th><th>Tipo</th><th>Estado</th><th>Prestado</th><th>Pagado</th><th>Balance</th><th>Vencido</th></tr></thead><tbody>
    {data.prestamos.map(p=><tr key={p.prestamoId}><td>PR-{String(p.prestamoId).padStart(5,'0')}</td><td>{p.tipo}</td><td><span className={`detail-status ${p.estado.toLowerCase()}`}>{p.estado}</span></td><td>{money(p.montoPrestado)}</td><td>{money(p.pagado)}</td><td><b>{money(p.balance)}</b></td><td className={p.vencido>0?'overdue-value':''}>{p.vencido>0?`${money(p.vencido)} · ${p.diasAtraso}d`:'—'}</td></tr>)}
   </tbody></table></div>
  </section>}

  {tab==='pagos'&&<section className="client-table-card">
   <div className="client-section-head"><div><span>PAGOS Y ABONOS</span><h3>{data.movimientos.length} movimientos</h3></div></div>
   <div className="table-wrap"><table className="client-detail-table"><thead><tr><th>Fecha</th><th>Préstamo</th><th>Concepto</th><th>Monto</th><th>Estado</th><th>Recibo</th></tr></thead><tbody>
    {data.movimientos.map(m=><tr key={m.id}><td>{date(m.fecha)}</td><td>PR-{String(m.prestamoId).padStart(5,'0')}</td><td>{m.concepto}</td><td><b>{money(m.monto)}</b></td><td>{m.estado}</td><td>{m.recibo||'—'}</td></tr>)}
   </tbody></table></div>
  </section>}

  {tab==='recibos'&&<section className="client-table-card">
   <div className="client-section-head"><div><span>RECIBOS</span><h3>{recibos.length} documentos</h3></div></div>
   <div className="table-wrap"><table className="client-detail-table"><thead><tr><th>Número</th><th>Fecha</th><th>Préstamo</th><th>Tipo</th><th>Monto</th><th>Estado</th><th></th></tr></thead><tbody>
    {recibos.map(r=><tr key={r.id}><td>{r.numero}</td><td>{date(r.fecha)}</td><td>PR-{String(r.prestamoId).padStart(5,'0')}</td><td>{r.tipoPago}</td><td><b>{money(r.monto)}</b></td><td>{r.estado}</td><td><button className="receipt-open" onClick={()=>openPdf(`/api/recibos/${r.id}/pdf`,`recibo-${r.id}`)} disabled={opening===`recibo-${r.id}`}>{opening===`recibo-${r.id}`?'Abriendo…':'PDF'}</button></td></tr>)}
   </tbody></table></div>
  </section>}

  {tab==='historial'&&<section className="client-history-card">
   <div className="client-section-head"><div><span>HISTORIAL DEL CLIENTE</span><h3>{data.historial.length} eventos</h3></div></div>
   {data.historial.length?<div className="client-timeline">{data.historial.map(h=>
    <div key={h.id}><span className="timeline-dot"/><div><small>{date(h.fecha)} · PR-{String(h.prestamoId).padStart(5,'0')}</small><b>{h.accion.replaceAll('_',' ')}</b><p>{h.descripcion||'Sin descripción adicional.'}</p></div></div>
   )}</div>:<p className="empty-detail client-history-empty">Este cliente todavía no tiene eventos registrados en el historial.</p>}
  </section>}
 </section>
}
