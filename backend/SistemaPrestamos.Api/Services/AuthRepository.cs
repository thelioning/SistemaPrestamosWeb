using Npgsql;
namespace SistemaPrestamos.Api.Services;

public sealed class AuthRepository(NpgsqlDataSource dataSource)
{
    public async Task<(int Id, string Name, string Username, string Hash, string Role)?> FindAsync(string username)
    {
        await using var command = dataSource.CreateCommand("SELECT id_usuario,nombre,usuario,clave_hash,rol FROM prestamos.usuarios WHERE LOWER(usuario)=LOWER($1) AND estado='ACTIVO'");
        command.Parameters.AddWithValue(username.Trim());
        await using var reader = await command.ExecuteReaderAsync();
        return await reader.ReadAsync() ? (reader.GetInt32(0), reader.GetString(1), reader.GetString(2), reader.GetString(3), reader.GetString(4)) : null;
    }
    public async Task<bool> HasUsersAsync()
    {
        await using var command = dataSource.CreateCommand("SELECT EXISTS(SELECT 1 FROM prestamos.usuarios)");
        return (bool)(await command.ExecuteScalarAsync())!;
    }
    public async Task<int> CreateAdminAsync(string name, string username, string hash)
    {
        await using var command = dataSource.CreateCommand("INSERT INTO prestamos.usuarios(nombre,usuario,clave_hash,rol) VALUES ($1,$2,$3,'ADMIN') RETURNING id_usuario");
        command.Parameters.AddWithValue(name.Trim()); command.Parameters.AddWithValue(username.Trim()); command.Parameters.AddWithValue(hash);
        return (int)(await command.ExecuteScalarAsync())!;
    }
    public async Task MarkAccessAsync(int id){await using var command=dataSource.CreateCommand("UPDATE prestamos.usuarios SET ultimo_acceso=current_timestamp WHERE id_usuario=$1");command.Parameters.AddWithValue(id);await command.ExecuteNonQueryAsync();}
}
