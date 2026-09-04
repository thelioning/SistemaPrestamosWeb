using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SistemaPrestamos.Api.Services;
namespace SistemaPrestamos.Api.Controllers;
[ApiController,Authorize,Route("api/reportes")]
public sealed class ReportesController(ReporteRepository repository,ReportePdfService pdf):ControllerBase
{
 [HttpGet("cartera")]public async Task<IActionResult> Cartera()=>Ok(await repository.CarteraAsync());
 [HttpGet("cartera/pdf")]public async Task<IActionResult> CarteraPdf()=>File(await pdf.CarteraAsync(),"application/pdf",$"cartera-general-{DateTime.Today:yyyyMMdd}.pdf");
 [HttpGet("clientes/{id:int}/estado-cuenta")]public async Task<IActionResult> Estado(int id){var d=await repository.EstadoCuentaAsync(id);return d is null?NotFound():Ok(d);}
 [HttpGet("clientes/{id:int}/estado-cuenta/pdf")]public async Task<IActionResult> EstadoPdf(int id){try{return File(await pdf.EstadoCuentaAsync(id),"application/pdf",$"estado-cuenta-{id:D4}.pdf");}catch(FileNotFoundException){return NotFound();}}
}
