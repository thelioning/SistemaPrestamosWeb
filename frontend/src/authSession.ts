export function ensureAuthorized(response:Response){
  if(response.status!==401)return
  sessionStorage.removeItem('token')
  window.location.reload()
  throw new Error('La sesión venció. Inicie sesión nuevamente.')
}
