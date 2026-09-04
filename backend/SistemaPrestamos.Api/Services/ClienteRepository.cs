using Npgsql;
namespace SistemaPrestamos.Api.Services;

public sealed record ClienteDto(int Id, string Nombre, string? Telefono, string? Direccion, string? Documento, string Estado, DateTime FechaRegistro);
public sealed record CrearClienteRequest(string Nombre, string? Telefono, string? Direccion, string? Documento);
public sealed class ClienteRepository(NpgsqlDataSource dataSource)
{
    public async Task<List<ClienteDto>> ListAsync(string? search)
    {
        await using var command = dataSource.CreateCommand("SELECT id_cliente,nombre,telefono,direccion,documento,estado,fecha_registro FROM prestamos.cliente WHERE $1='' OR nombre ILIKE '%'||$1||'%' OR COALESCE(documento,'') ILIKE '%'||$1||'%' ORDER BY nombre");
        command.Parameters.AddWithValue(search?.Trim() ?? ""); var result = new List<ClienteDto>();
        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync()) result.Add(new(reader.GetInt32(0), reader.GetString(1), reader.IsDBNull(2)?null:reader.GetString(2), reader.IsDBNull(3)?null:reader.GetString(3), reader.IsDBNull(4)?null:reader.GetString(4), reader.GetString(5), reader.GetDateTime(6)));
        return result;
    }
    public async Task<int> CreateAsync(CrearClienteRequest request)
    {
        await using var command = dataSource.CreateCommand("INSERT INTO prestamos.cliente(nombre,telefono,direccion,documento) VALUES ($1,NULLIF($2,''),NULLIF($3,''),NULLIF($4,'')) RETURNING id_cliente");
        command.Parameters.AddWithValue(request.Nombre.Trim()); command.Parameters.AddWithValue(request.Telefono?.Trim()??""); command.Parameters.AddWithValue(request.Direccion?.Trim()??""); command.Parameters.AddWithValue(request.Documento?.Trim()??"");
        return (int)(await command.ExecuteScalarAsync())!;
    }
}
