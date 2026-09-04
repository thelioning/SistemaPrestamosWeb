using System.Security.Claims;using Microsoft.AspNetCore.Authorization;using Microsoft.AspNetCore.Mvc;using Npgsql;using SistemaPrestamos.Api.Services;
namespace SistemaPrestamos.Api.Controllers;
[ApiController,Authorize(Roles="ADMIN"),Route("api/usuarios")]
public sealed class UsuariosController(UsuarioRepository repository):ControllerBase
{
 int Actor=>int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)??User.FindFirstValue("sub")!);
 [HttpGet]public async Task<IActionResult> List()=>Ok(await repository.ListAsync());
 [HttpPost]public async Task<IActionResult> Create(CrearUsuarioRequest q){try{var id=await repository.CreateAsync(q,Actor);return Created($"api/usuarios/{id}",new{id});}catch(PostgresException ex)when(ex.SqlState==PostgresErrorCodes.UniqueViolation){return Conflict(new{message="Ese nombre de usuario ya está registrado."});}catch(ArgumentException ex){return BadRequest(new{message=ex.Message});}}
 [HttpPut("{id:int}")]public async Task<IActionResult> Update(int id,ActualizarUsuarioRequest q){try{await repository.UpdateAsync(id,q,Actor);return NoContent();}catch(KeyNotFoundException){return NotFound();}catch(ArgumentException ex){return BadRequest(new{message=ex.Message});}}
 [HttpPost("{id:int}/clave")]public async Task<IActionResult> Password(int id,CambiarClaveUsuarioRequest q){try{await repository.ResetPasswordAsync(id,q.Clave,Actor);return NoContent();}catch(KeyNotFoundException){return NotFound();}catch(ArgumentException ex){return BadRequest(new{message=ex.Message});}}
}
