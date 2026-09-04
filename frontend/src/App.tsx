import { useEffect, useState } from 'react'
import type { FormEvent } from 'react'
import './App.css'
import './Atrasos.css'
import './Permisos.css'
import PrestamosView from './PrestamosView'
import PagosView from './PagosView'
import ReportesView from './ReportesView'
import CierreCajaView from './CierreCajaView'
import UsuariosView from './UsuariosView'
import { ensureAuthorized } from './authSession'

const API = import.meta.env.VITE_API_URL ?? 'http://localhost:5159'
type Cliente = { id:number; nombre:string; telefono?:string; documento?:string; estado:string }
type Dashboard = { totalPrestado:number; totalCobrado:number; totalPendiente:number; prestamosActivos:number; prestamosSaldados:number; prestamosAtrasados:number; prestamosSan:number; prestamosRedito:number }
type ClienteAtrasado = {clienteId:number;cliente:string;telefono?:string;prestamos:number;cuotasVencidas:number;totalVencido:number;diasAtraso:number;primerVencimiento:string;prestamoId:number}
type Atrasos = {resumen:{clientesAtrasados:number;prestamosAtrasados:number;cuotasVencidas:number;totalVencido:number;maximoDiasAtraso:number};clientes:ClienteAtrasado[]}
type CurrentUser = {id:number;name:string;username:string;role:'ADMIN'|'COBRADOR'|'CONSULTA'}

async function api(path:string, token:string, options:RequestInit={}) {
  const response = await fetch(`${API}${path}`, { ...options, headers:{ 'Content-Type':'application/json', Authorization:`Bearer ${token}`, ...options.headers } })
  if(token) ensureAuthorized(response)
  if (!response.ok) throw new Error((await response.json().catch(()=>({}))).message ?? 'No fue posible completar la solicitud.')
  return response.json()
}

function money(value=0){ return new Intl.NumberFormat('es-DO',{style:'currency',currency:'DOP'}).format(value) }

export default function App(){
  const [token,setToken]=useState(()=>sessionStorage.getItem('token')??'')
  const [view,setView]=useState<'dashboard'|'clientes'|'prestamos'|'pagos'|'reportes'|'caja'|'usuarios'>('dashboard')
  const [currentUser,setCurrentUser]=useState<CurrentUser|null>(null)
  const [dashboard,setDashboard]=useState<Dashboard|null>(null)
  const [atrasos,setAtrasos]=useState<Atrasos|null>(null)
  const [clientes,setClientes]=useState<Cliente[]>([])
  const [buscar,setBuscar]=useState('')
  const [mostrarFormulario,setMostrarFormulario]=useState(false)
  const [error,setError]=useState('')

  useEffect(()=>{ if(!token)return; Promise.all([api('/api/dashboard',token),api('/api/clientes',token),api('/api/atrasos',token),api('/api/auth/me',token)])
    .then(([d,c,a,u])=>{setDashboard(d);setClientes(c);setAtrasos(a);setCurrentUser(u)}).catch(e=>setError(e.message)) },[token])
  async function refreshSummary(){const[d,a]=await Promise.all([api('/api/dashboard',token),api('/api/atrasos',token)]);setDashboard(d);setAtrasos(a)}

  async function login(event:FormEvent<HTMLFormElement>){ event.preventDefault(); setError(''); const data=new FormData(event.currentTarget)
    try { const result=await api('/api/auth/login','',{method:'POST',body:JSON.stringify({usuario:data.get('usuario'),clave:data.get('clave')}),headers:{Authorization:''}}); sessionStorage.setItem('token',result.token);setCurrentUser(result.user);setToken(result.token) }
    catch(e){setError((e as Error).message)} }

  async function crearCliente(event:FormEvent<HTMLFormElement>){event.preventDefault();setError('');const form=event.currentTarget;const data=new FormData(form)
    try{await api('/api/clientes',token,{method:'POST',body:JSON.stringify(Object.fromEntries(data))});setClientes(await api('/api/clientes',token));form.reset();setMostrarFormulario(false)}
    catch(e){setError((e as Error).message)}}

  if(!token) return <main className="login-shell"><section className="brand"><span>SAN & RÉDITO</span><h1>Control claro de cada préstamo.</h1><p>Clientes, cobros, saldos y recibos en un solo lugar.</p></section><form className="login-card" onSubmit={login}><p className="eyebrow">ACCESO SEGURO</p><h2>Bienvenido</h2><label>Usuario<input name="usuario" autoComplete="username" required/></label><label>Contraseña<input name="clave" type="password" autoComplete="current-password" required/></label>{error&&<p className="error">{error}</p>}<button>Iniciar sesión</button></form></main>

  return <div className={`app role-${currentUser?.role.toLowerCase()??'consulta'}`}><aside><div className="logo">S&R</div><nav><button className={view==='dashboard'?'active':''} onClick={()=>setView('dashboard')}>Resumen</button><button className={view==='clientes'?'active':''} onClick={()=>setView('clientes')}>Clientes</button><button className={view==='prestamos'?'active':''} onClick={()=>setView('prestamos')}>Préstamos</button><button className={view==='pagos'?'active':''} onClick={()=>setView('pagos')}>Pagos</button><button className={view==='reportes'?'active':''} onClick={()=>setView('reportes')}>Reportes</button>{currentUser?.role==='ADMIN'&&<><button className={view==='caja'?'active':''} onClick={()=>setView('caja')}>Cierre de caja</button><button className={view==='usuarios'?'active':''} onClick={()=>setView('usuarios')}>Usuarios</button></>}</nav><button className="logout" onClick={()=>{sessionStorage.clear();setCurrentUser(null);setToken('')}}>Cerrar sesión</button></aside><main className="content">
    <header><div><p className="eyebrow">SISTEMA DE PRÉSTAMOS</p><h1>{view==='dashboard'?'Resumen general':view==='clientes'?'Clientes':view==='prestamos'?'Préstamos':view==='pagos'?'Pagos':view==='reportes'?'Reportes':view==='caja'?'Cierre de caja':'Usuarios'}</h1></div><span className="status">● Base de desarrollo</span></header>{error&&<p className="error banner">{error}</p>}
    {view==='dashboard'&&<>{dashboard&&atrasos?<><section className="cards dashboard-cards"><article><span>Total prestado</span><strong>{money(dashboard.totalPrestado)}</strong></article><article><span>Total cobrado</span><strong>{money(dashboard.totalCobrado)}</strong></article><article><span>Saldo pendiente</span><strong>{money(dashboard.totalPendiente)}</strong></article><article className={atrasos.resumen.totalVencido>0?'overdue-card':''}><span>Total vencido</span><strong>{money(atrasos.resumen.totalVencido)}</strong><small>{atrasos.resumen.clientesAtrasados} clientes requieren atención</small></article></section><section className="panel"><h2>Estado de la cartera</h2><div className="metrics"><div><b>{dashboard.prestamosActivos}</b><span>Activos</span></div><div><b>{dashboard.prestamosSaldados}</b><span>Saldados</span></div><div className={atrasos.resumen.prestamosAtrasados>0?'metric-alert':''}><b>{atrasos.resumen.prestamosAtrasados}</b><span>Con atraso real</span></div><div><b>{dashboard.prestamosSan}</b><span>SAN</span></div><div><b>{dashboard.prestamosRedito}</b><span>Rédito</span></div></div></section><section className="overdue-panel"><div className="overdue-heading"><div><p className="eyebrow">SEGUIMIENTO DE COBROS</p><h2>Control de atrasos</h2><p>Cuotas SAN vencidas con saldo pendiente, agrupadas una sola vez por cliente.</p></div>{atrasos.resumen.clientesAtrasados>0&&<button onClick={()=>setView('pagos')}>Registrar un pago</button>}</div>{atrasos.resumen.clientesAtrasados>0?<><div className="overdue-summary"><div><span>Clientes</span><b>{atrasos.resumen.clientesAtrasados}</b></div><div><span>Cuotas vencidas</span><b>{atrasos.resumen.cuotasVencidas}</b></div><div><span>Mayor atraso</span><b>{atrasos.resumen.maximoDiasAtraso} días</b></div><div><span>Total vencido</span><b>{money(atrasos.resumen.totalVencido)}</b></div></div><div className="overdue-table-wrap"><table className="overdue-table"><thead><tr><th>Cliente</th><th>Préstamos</th><th>Cuotas</th><th>Atraso</th><th>Total vencido</th></tr></thead><tbody>{atrasos.clientes.map(c=><tr key={c.clienteId}><td><div className="overdue-client"><span>{c.cliente.split(' ').slice(0,2).map(n=>n[0]).join('').toUpperCase()}</span><div><b>{c.cliente}</b><small>{c.telefono??`Cliente #${String(c.clienteId).padStart(4,'0')}`}</small></div></div></td><td>{c.prestamos}</td><td>{c.cuotasVencidas}</td><td><span className={`delay-badge ${c.diasAtraso>30?'critical':c.diasAtraso>7?'warning':''}`}>{c.diasAtraso} días</span></td><td><b>{money(c.totalVencido)}</b></td></tr>)}</tbody></table></div></>:<div className="portfolio-clear"><span>✓</span><div><b>Cartera al día</b><p>No existen cuotas SAN vencidas con balances pendientes.</p></div></div>}</section></>:<p>Cargando resumen…</p>}</>}
    {view==='clientes'&&<section className="clients-page"><div className="clients-toolbar"><div className="client-stats"><div><strong>{clientes.length}</strong><span>Total de clientes</span></div><i/><div><strong>{clientes.filter(c=>c.estado==='ACTIVO').length}</strong><span>Clientes activos</span></div></div><button className="new-client" onClick={()=>setMostrarFormulario(true)}><span>＋</span> Nuevo cliente</button></div><section className="client-directory"><div className="directory-head"><div><h2>Directorio de clientes</h2><p>Consulte y administre la información de sus clientes.</p></div><label className="search"><span>⌕</span><input value={buscar} onChange={e=>setBuscar(e.target.value)} placeholder="Buscar cliente" aria-label="Buscar clientes"/></label></div><div className="table-wrap"><table><thead><tr><th>Cliente</th><th>Documento</th><th>Teléfono</th><th>Estado</th></tr></thead><tbody>{clientes.filter(c=>(c.nombre+' '+(c.documento??'')).toLowerCase().includes(buscar.toLowerCase())).map(c=><tr key={c.id}><td><div className="client-name"><span className="avatar">{c.nombre.split(' ').slice(0,2).map(n=>n[0]).join('').toUpperCase()}</span><div><b>{c.nombre}</b><small>Cliente #{String(c.id).padStart(4,'0')}</small></div></div></td><td className="muted">{c.documento??'—'}</td><td className="muted">{c.telefono??'—'}</td><td><span className="pill"><i/> {c.estado}</span></td></tr>)}</tbody></table></div></section>{mostrarFormulario&&<div className="modal-backdrop" onMouseDown={()=>setMostrarFormulario(false)}><form className="client-modal" onSubmit={crearCliente} onMouseDown={e=>e.stopPropagation()}><div className="modal-head"><div><span>Nuevo cliente</span><h2>Información personal</h2></div><button type="button" className="close-button" onClick={()=>setMostrarFormulario(false)} aria-label="Cerrar">×</button></div><p className="form-help">Registre los datos principales del cliente. Los campos opcionales pueden completarse después.</p><label>Nombre completo<input name="nombre" maxLength={50} placeholder="Ej. María Rodríguez" autoFocus required/></label><div className="field-row"><label>Documento <small>Opcional</small><input name="documento" maxLength={30} placeholder="Número de cédula"/></label><label>Teléfono <small>Opcional</small><input name="telefono" maxLength={20} placeholder="809-000-0000"/></label></div><label>Dirección <small>Opcional</small><textarea name="direccion" rows={3} placeholder="Sector, calle y referencia"/></label><div className="modal-actions"><button type="button" className="cancel-button" onClick={()=>setMostrarFormulario(false)}>Cancelar</button><button>Guardar cliente</button></div></form></div>}</section>}
    {view==='prestamos'&&<PrestamosView token={token} clientes={clientes} onChanged={refreshSummary}/>} 
    {view==='pagos'&&<PagosView token={token} onChanged={refreshSummary}/>} 
    {view==='reportes'&&<ReportesView token={token} clientes={clientes}/>} 
    {view==='caja'&&currentUser?.role==='ADMIN'&&<CierreCajaView token={token} onChanged={refreshSummary}/>} 
    {view==='usuarios'&&currentUser?.role==='ADMIN'&&<UsuariosView token={token} currentId={currentUser.id}/>} 
  </main></div>
}
