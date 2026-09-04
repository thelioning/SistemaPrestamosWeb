using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using SistemaPrestamos.Api.Services;
using System.IdentityModel.Tokens.Jwt;
namespace SistemaPrestamos.Api.Controllers;

[ApiController,Authorize,Route("api/pagos")]
public sealed class PagosController(PagoRepository repository,ReciboPdfService pdf):ControllerBase
{
 [HttpGet] public async Task<IActionResult> List()=>Ok(await repository.ListAsync());
 [HttpGet("prestamos")] public async Task<IActionResult> Loans()=>Ok(await repository.GetLoansAsync());
 [HttpGet("prestamos/{id:int}/cuotas")] public async Task<IActionResult> Installments(int id)=>Ok(await repository.GetInstallmentsAsync(id));
 [Authorize(Roles="ADMIN,COBRADOR"),HttpPost] public async Task<IActionResult> Register(RegistrarPagoRequest request)
 {
  if(request.PrestamoId<=0||request.Fecha==default)return BadRequest(new{message="Seleccione el préstamo y la fecha."});
  var type=request.TipoPago.ToUpperInvariant();
  if(type=="CUOTA_SAN"&&(request.NumeroCuota<=0||request.Monto<=0))return BadRequest(new{message="Seleccione la cuota e indique un monto válido."});
  if((type is "REDITO" or "ABONO_CAPITAL")&&request.Monto<=0)return BadRequest(new{message="Indique un monto válido."});
  if(type=="MIXTO"&&((request.MontoRedito??0)+(request.MontoCapital??0)<=0))return BadRequest(new{message="El pago mixto debe ser mayor que cero."});
 try{var result=await repository.RegisterAsync(request);await pdf.EnsureByPaymentAsync(result.PagoId);return Ok(result);}catch(PostgresException ex){return BadRequest(new{message=ex.MessageText});}catch(ArgumentException ex){return BadRequest(new{message=ex.Message});}
 }
 [Authorize(Roles="ADMIN"),HttpPost("{id:int}/anular")]
 public async Task<IActionResult> Annul(int id,AnularPagoRequest request)
 {
  if(string.IsNullOrWhiteSpace(request.Motivo)||request.Motivo.Trim().Length<8)return BadRequest(new{message="Indique un motivo de al menos 8 caracteres."});
  var usuario=User.FindFirst(JwtRegisteredClaimNames.UniqueName)?.Value??User.Identity?.Name??"Sistema";
  try{return Ok(await repository.AnnulAsync(id,request.Motivo.Trim(),usuario));}catch(PostgresException ex){return BadRequest(new{message=ex.MessageText});}
 }
}
