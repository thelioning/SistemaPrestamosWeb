using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using SistemaPrestamos.Api.Services;

namespace SistemaPrestamos.Api.Controllers;

[ApiController, Authorize, Route("api/prestamos")]
public sealed class PrestamosController(PrestamoRepository repository) : ControllerBase
{
    [HttpGet] public async Task<IActionResult> List(string? buscar, string? tipo, string? estado) => Ok(await repository.ListAsync(buscar,tipo,estado));
    [HttpGet("reenganches/elegibles")] public async Task<IActionResult> EligibleRenewals() => Ok(await repository.GetEligibleRenewalsAsync());
    [HttpGet("{id:int}")] public async Task<IActionResult> Get(int id)
    {
        var loan=await repository.GetAsync(id); return loan is null ? NotFound() : Ok(new { prestamo=loan, cuotas=await repository.GetScheduleAsync(id) });
    }
    [Authorize(Roles="ADMIN,COBRADOR"),HttpPost] public async Task<IActionResult> Create(CrearPrestamoRequest request)
    {
        if (request.ClienteId<=0 || request.MontoPrestado<=0 || request.FechaInicio==default) return BadRequest(new {message="Complete los datos obligatorios."});
        var type=request.Tipo.ToUpperInvariant();
        if (type is not ("SAN" or "REDITO")) return BadRequest(new {message="El tipo de préstamo no es válido."});
        if (type=="SAN" && (request.Cuota<=0 || request.Periodos<=0)) return BadRequest(new {message="Indique una cuota y cantidad de períodos válidas."});
        if (type=="REDITO" && request.Redito<=0) return BadRequest(new {message="Indique un rédito válido."});
        try { var id=await repository.CreateAsync(request); return Created($"api/prestamos/{id}",new{id}); }
        catch(PostgresException ex){ return BadRequest(new {message=ex.MessageText}); }
    }
    [Authorize(Roles="ADMIN"),HttpPost("reenganches")] public async Task<IActionResult> CreateRenewal(CrearReengancheRequest request)
    {
        if(request.PrestamoOrigenId<=0||request.MontoNuevo<=0||request.Cuota<=0||request.Periodos<=0||request.FechaInicio==default) return BadRequest(new{message="Complete las condiciones del reenganche."});
        try{var id=await repository.CreateRenewalAsync(request);return Created($"api/prestamos/{id}",new{id});}
        catch(PostgresException ex){return BadRequest(new{message=ex.MessageText});}
    }
    [Authorize(Roles="ADMIN"),HttpPatch("{id:int}")] public async Task<IActionResult> Update(int id, ActualizarPrestamoRequest request)
    {
        var allowed=new[]{"ACTIVO","ATRASADO","CANCELADO","RENEGOCIADO"};
        if(!allowed.Contains(request.Estado.ToUpperInvariant())) return BadRequest(new{message="Estado no permitido."});
        return await repository.UpdateAsync(id,request) ? NoContent() : NotFound();
    }
}
