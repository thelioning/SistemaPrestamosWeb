using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SistemaPrestamos.Api.Services;

namespace SistemaPrestamos.Api.Controllers;

[ApiController, Authorize, Route("api/dashboard")]
public sealed class DashboardController(DashboardRepository repository) : ControllerBase
{
    [HttpGet] public async Task<IActionResult> Get() => Ok(await repository.GetAsync());
}
