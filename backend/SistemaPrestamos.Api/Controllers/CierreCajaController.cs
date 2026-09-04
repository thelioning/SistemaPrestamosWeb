using System.IdentityModel.Tokens.Jwt;using Microsoft.AspNetCore.Authorization;using Microsoft.AspNetCore.Mvc;using Npgsql;using SistemaPrestamos.Api.Services;
namespace SistemaPrestamos.Api.Controllers;
[ApiController,Authorize(Roles="ADMIN"),Route("api/cierre-caja")]
public sealed class CierreCajaController(CierreCajaRepository repository,CierreCajaPdfService pdf):ControllerBase
{
 [HttpGet("dia/{fecha}")]public async Task<IActionResult> Day(DateOnly fecha)=>Ok(await repository.DiaAsync(fecha));
 [HttpGet("historial")]public async Task<IActionResult> History()=>Ok(await repository.HistoryAsync());
 [HttpPost]public async Task<IActionResult> Close(CerrarCajaRequest request){var user=User.FindFirst(JwtRegisteredClaimNames.UniqueName)?.Value??User.Identity?.Name??"Sistema";try{return Ok(await repository.CloseAsync(request,user));}catch(PostgresException ex){return BadRequest(new{message=ex.MessageText});}}
 [HttpGet("{fecha}/pdf")]public async Task<IActionResult> Pdf(DateOnly fecha){try{return File(await pdf.GenerateAsync(fecha),"application/pdf",$"cierre-caja-{fecha:yyyyMMdd}.pdf");}catch(InvalidOperationException ex){return BadRequest(new{message=ex.Message});}}
}
