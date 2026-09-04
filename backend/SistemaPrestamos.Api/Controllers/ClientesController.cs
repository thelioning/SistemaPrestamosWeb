using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SistemaPrestamos.Api.Services;

namespace SistemaPrestamos.Api.Controllers;

[ApiController, Authorize, Route("api/clientes")]
public sealed class ClientesController(ClienteRepository repository) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List([FromQuery] string? buscar) => Ok(await repository.ListAsync(buscar));

    [Authorize(Roles="ADMIN,COBRADOR"),HttpPost]
    public async Task<IActionResult> Create(CrearClienteRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Nombre) || request.Nombre.Trim().Length > 50) return BadRequest(new { message = "El nombre es obligatorio y admite hasta 50 caracteres." });
        var id = await repository.CreateAsync(request);
        return Created($"api/clientes/{id}", new { id });
    }
}
