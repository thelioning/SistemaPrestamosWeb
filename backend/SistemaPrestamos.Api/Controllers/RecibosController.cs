using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SistemaPrestamos.Api.Services;
namespace SistemaPrestamos.Api.Controllers;
[ApiController,Authorize,Route("api/recibos")]
public sealed class RecibosController(ReciboRepository repository,ReciboPdfService pdf):ControllerBase
{
 [HttpGet("clientes")]public async Task<IActionResult> Clients()=>Ok(await repository.ClientsAsync());
 [HttpGet("clientes/{id:int}")]public async Task<IActionResult> ByClient(int id){var rows=await repository.ByClientAsync(id);return Ok(User.IsInRole("ADMIN")?rows:rows.Select(x=>x with{PuedeAnular=false}));}
 [HttpGet("{id:int}/pdf")]public async Task<IActionResult> Pdf(int id){try{var path=await pdf.EnsureAsync(id);return PhysicalFile(path,"application/pdf",Path.GetFileName(path));}catch(FileNotFoundException){return NotFound();}}
}
