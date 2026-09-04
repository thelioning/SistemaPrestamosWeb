using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using Npgsql;
using SistemaPrestamos.Api.Services;
using QuestPDF.Infrastructure;

var builder = WebApplication.CreateBuilder(args);
var connectionString = builder.Configuration.GetConnectionString("Prestamos")
    ?? throw new InvalidOperationException("Falta ConnectionStrings:Prestamos.");
var jwtKey = builder.Configuration["Jwt:Key"]
    ?? throw new InvalidOperationException("Falta Jwt:Key.");

builder.Services.AddSingleton(NpgsqlDataSource.Create(connectionString));
builder.Services.AddSingleton<PasswordService>();
builder.Services.AddSingleton<TokenService>();
builder.Services.AddScoped<AuthRepository>();
builder.Services.AddScoped<ClienteRepository>();
builder.Services.AddScoped<DashboardRepository>();
builder.Services.AddScoped<PrestamoRepository>();
builder.Services.AddScoped<PagoRepository>();
builder.Services.AddScoped<ReciboRepository>();
builder.Services.AddScoped<ReciboPdfService>();
builder.Services.AddScoped<AtrasoRepository>();
builder.Services.AddScoped<ReporteRepository>();
builder.Services.AddScoped<ReportePdfService>();
builder.Services.AddScoped<CierreCajaRepository>();
builder.Services.AddScoped<CierreCajaPdfService>();
builder.Services.AddScoped<UsuarioRepository>();
builder.Services.AddControllers();
builder.Services.AddCors(options => options.AddPolicy("Frontend", policy =>
    policy.WithOrigins(builder.Configuration["Frontend:Url"] ?? "http://localhost:5173")
        .AllowAnyHeader().AllowAnyMethod()));
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(options =>
    options.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuer = true, ValidateAudience = true, ValidateLifetime = true, ValidateIssuerSigningKey = true,
        ValidIssuer = builder.Configuration["Jwt:Issuer"],
        ValidAudience = builder.Configuration["Jwt:Audience"],
        IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtKey)),
        ClockSkew = TimeSpan.FromMinutes(1)
    });
builder.Services.AddAuthorization();

var app = builder.Build();
QuestPDF.Settings.License = LicenseType.Community;
if (!app.Environment.IsDevelopment())
    app.UseHttpsRedirection();
app.UseCors("Frontend");
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.MapGet("/health", () => Results.Ok(new { status = "ok" })).AllowAnonymous();
app.Run();
