using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SistemaPrestamos.Api.Services;
using System.Security.Claims;

namespace SistemaPrestamos.Api.Controllers;

public sealed record LoginRequest(string Usuario, string Clave);
public sealed record BootstrapRequest(string Nombre, string Usuario, string Clave);

[ApiController, Route("api/auth")]
public sealed class AuthController(AuthRepository repository, PasswordService passwords, TokenService tokens, IConfiguration configuration) : ControllerBase
{
    [AllowAnonymous, HttpPost("login")]
    public async Task<IActionResult> Login(LoginRequest request)
    {
        var user = await repository.FindAsync(request.Usuario);
        if (user is null || !passwords.Verify(request.Clave, user.Value.Hash)) return Unauthorized(new { message = "Usuario o contraseña incorrectos." });
        await repository.MarkAccessAsync(user.Value.Id);
        return Ok(new { token = tokens.Create(user.Value.Id, user.Value.Username, user.Value.Name, user.Value.Role), user = new { id=user.Value.Id,user.Value.Name, user.Value.Username, user.Value.Role } });
    }

    [AllowAnonymous, HttpPost("bootstrap")]
    public async Task<IActionResult> Bootstrap(BootstrapRequest request, [FromHeader(Name = "X-Setup-Key")] string? setupKey)
    {
        if (string.IsNullOrWhiteSpace(configuration["Setup:Key"]) || setupKey != configuration["Setup:Key"]) return Unauthorized();
        if (await repository.HasUsersAsync()) return Conflict(new { message = "El administrador inicial ya fue creado." });
        if (request.Clave.Length < 10) return BadRequest(new { message = "La contraseña debe tener al menos 10 caracteres." });
        var id = await repository.CreateAdminAsync(request.Nombre, request.Usuario, passwords.Hash(request.Clave));
        return Created("api/auth/login", new { id });
    }
    [Authorize,HttpGet("me")]
    public IActionResult Me()=>Ok(new{id=int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)??User.FindFirstValue("sub")!),name=User.Identity!.Name,username=User.FindFirstValue("unique_name"),role=User.FindFirstValue(ClaimTypes.Role)});
}
