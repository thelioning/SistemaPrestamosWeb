using Npgsql;
namespace SistemaPrestamos.Api.Services;

public sealed record DashboardDto(decimal TotalPrestado, decimal TotalCobrado, decimal TotalPendiente, decimal TotalReditoCobrado, decimal TotalCapitalAbonado, long CantidadPrestamos, long PrestamosActivos, long PrestamosSaldados, long PrestamosAtrasados, long PrestamosSan, long PrestamosRedito);
public sealed class DashboardRepository(NpgsqlDataSource dataSource)
{
    public async Task<DashboardDto> GetAsync()
    {
        await using var command = dataSource.CreateCommand("SELECT * FROM prestamos.vw_dashboard"); await using var reader = await command.ExecuteReaderAsync();
        if (!await reader.ReadAsync()) return new(0,0,0,0,0,0,0,0,0,0,0);
        return new(reader.GetDecimal(0),reader.GetDecimal(1),reader.GetDecimal(2),reader.GetDecimal(3),reader.GetDecimal(4),reader.GetInt64(5),reader.GetInt64(6),reader.GetInt64(7),reader.GetInt64(8),reader.GetInt64(9),reader.GetInt64(10));
    }
}
