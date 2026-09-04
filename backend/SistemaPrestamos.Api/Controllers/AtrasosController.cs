using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SistemaPrestamos.Api.Services;
namespace SistemaPrestamos.Api.Controllers;

[ApiController,Authorize,Route("api/atrasos")]
public sealed class AtrasosController(AtrasoRepository repository):ControllerBase
{
 [HttpGet] public async Task<IActionResult> Get()=>Ok(await repository.GetAsync());
}
