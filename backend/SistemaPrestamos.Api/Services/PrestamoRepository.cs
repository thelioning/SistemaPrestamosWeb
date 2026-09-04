using Npgsql;

namespace SistemaPrestamos.Api.Services;

public sealed record PrestamoDto(int Id, int ClienteId, string Cliente, string Tipo, string Frecuencia, string Estado,
    decimal MontoPrestado, decimal? Cuota, int? Periodos, decimal? TotalPagar, decimal? Redito,
    decimal? CapitalPendiente, DateOnly FechaInicio, DateOnly? FechaFin, string? Observacion,
    decimal TotalPagadoSan, decimal TotalReditoPagado, decimal TotalCapitalAbonado, decimal SaldoPendiente,
    int? PrestamoOrigenId, decimal? MontoDescontado, decimal? MontoEntregado);
public sealed record CuotaDto(int Id, int Numero, DateOnly Vencimiento, decimal Programado, decimal Pagado, string Estado);
public sealed record CrearPrestamoRequest(int ClienteId, string Tipo, decimal MontoPrestado, string Frecuencia,
    DateOnly FechaInicio, decimal? Cuota, int? Periodos, decimal? Redito, string? Observacion);
public sealed record ActualizarPrestamoRequest(string Estado, string? Observacion);
public sealed record ReengancheElegibleDto(int Id, int ClienteId, string Cliente, decimal MontoOriginal, decimal SaldoPendiente, int CuotasPagadas, int TotalCuotas);
public sealed record CrearReengancheRequest(int PrestamoOrigenId, decimal MontoNuevo, decimal Cuota, int Periodos, string Frecuencia, DateOnly FechaInicio, string? Observacion);

public sealed class PrestamoRepository(NpgsqlDataSource dataSource)
{
    private const string SelectBase = """
        SELECT v.id_prestamo,v.id_cliente,v.cliente,v.tipo_prestamo,v.frecuencia,v.estado,v.monto_prestado,
               v.cuota,v.cantidad_periodos,v.total_a_pagar,v.monto_redito,v.capital_pendiente,v.fecha_inicio,
               v.fecha_fin_estimada,v.observacion,v.total_pagado_san,v.total_redito_pagado,
               v.total_capital_abonado,v.saldo_pendiente,p.id_prestamo_origen,p.monto_descontado,p.monto_entregado
        FROM prestamos.vw_prestamos_general v JOIN prestamos.prestamos p ON p.id_prestamo=v.id_prestamo
        """;

    public async Task<List<PrestamoDto>> ListAsync(string? search, string? type, string? status)
    {
        await using var command = dataSource.CreateCommand(SelectBase + "\n" + """
            WHERE ($1='' OR v.cliente ILIKE '%'||$1||'%' OR v.id_prestamo::text=$1)
              AND ($2='' OR v.tipo_prestamo=$2) AND ($3='' OR v.estado=$3)
            ORDER BY v.id_prestamo DESC
            """);
        command.Parameters.AddWithValue(search?.Trim() ?? "");
        command.Parameters.AddWithValue(type?.Trim().ToUpperInvariant() ?? "");
        command.Parameters.AddWithValue(status?.Trim().ToUpperInvariant() ?? "");
        var result = new List<PrestamoDto>();
        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync()) result.Add(Read(reader));
        return result;
    }

    public async Task<PrestamoDto?> GetAsync(int id)
    {
        await using var command = dataSource.CreateCommand(SelectBase + "\nWHERE v.id_prestamo=$1");
        command.Parameters.AddWithValue(id); await using var reader = await command.ExecuteReaderAsync();
        return await reader.ReadAsync() ? Read(reader) : null;
    }

    public async Task<List<CuotaDto>> GetScheduleAsync(int id)
    {
        await using var command = dataSource.CreateCommand("SELECT id_plan_pago,numero_cuota,fecha_vencimiento,monto_programado,monto_pagado,estado FROM prestamos.plan_pagos WHERE id_prestamo=$1 ORDER BY numero_cuota");
        command.Parameters.AddWithValue(id); var result = new List<CuotaDto>(); await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync()) result.Add(new(reader.GetInt32(0),reader.GetInt32(1),reader.GetFieldValue<DateOnly>(2),reader.GetDecimal(3),reader.GetDecimal(4),reader.GetString(5)));
        return result;
    }

    public async Task<int> CreateAsync(CrearPrestamoRequest request)
    {
        var san = request.Tipo.Equals("SAN", StringComparison.OrdinalIgnoreCase);
        var sql = san
            ? "SELECT prestamos.crear_prestamo_san($1,$2,$3,$4,$5,$6,$7)"
            : "SELECT prestamos.crear_prestamo_redito($1,$2,$3,$4,$5,$6)";
        await using var command = dataSource.CreateCommand(sql);
        command.Parameters.AddWithValue(request.ClienteId); command.Parameters.AddWithValue(request.MontoPrestado);
        if (san) { command.Parameters.AddWithValue(request.Cuota!.Value); command.Parameters.AddWithValue(request.Periodos!.Value); }
        else command.Parameters.AddWithValue(request.Redito!.Value);
        command.Parameters.AddWithValue(request.Frecuencia.ToUpperInvariant()); command.Parameters.AddWithValue(request.FechaInicio);
        command.Parameters.AddWithValue((object?)request.Observacion ?? DBNull.Value);
        return (int)(await command.ExecuteScalarAsync())!;
    }

    public async Task<List<ReengancheElegibleDto>> GetEligibleRenewalsAsync()
    {
        await using var command=dataSource.CreateCommand("""
          SELECT v.id_prestamo,v.id_cliente,v.cliente,v.monto_prestado,v.saldo_pendiente,
            COUNT(*) FILTER(WHERE pp.estado='PAGADA'),COUNT(pp.id_plan_pago)
          FROM prestamos.vw_prestamos_general v JOIN prestamos.plan_pagos pp ON pp.id_prestamo=v.id_prestamo
          WHERE v.tipo_prestamo='SAN' AND v.estado='ACTIVO' AND v.saldo_pendiente>0
          GROUP BY v.id_prestamo,v.id_cliente,v.cliente,v.monto_prestado,v.saldo_pendiente ORDER BY v.cliente
          """);
        var result=new List<ReengancheElegibleDto>(); await using var reader=await command.ExecuteReaderAsync();
        while(await reader.ReadAsync()) result.Add(new(reader.GetInt32(0),reader.GetInt32(1),reader.GetString(2),reader.GetDecimal(3),reader.GetDecimal(4),checked((int)reader.GetInt64(5)),checked((int)reader.GetInt64(6))));
        return result;
    }

    public async Task<int> CreateRenewalAsync(CrearReengancheRequest request)
    {
        await using var command=dataSource.CreateCommand("SELECT prestamos.crear_reenganche_san($1,$2,$3,$4,$5,$6,$7)");
        command.Parameters.AddWithValue(request.PrestamoOrigenId);command.Parameters.AddWithValue(request.MontoNuevo);command.Parameters.AddWithValue(request.Cuota);command.Parameters.AddWithValue(request.Periodos);command.Parameters.AddWithValue(request.Frecuencia.ToUpperInvariant());command.Parameters.AddWithValue(request.FechaInicio);command.Parameters.AddWithValue((object?)request.Observacion??DBNull.Value);
        return (int)(await command.ExecuteScalarAsync())!;
    }

    public async Task<bool> UpdateAsync(int id, ActualizarPrestamoRequest request)
    {
        await using var command = dataSource.CreateCommand("""
            UPDATE prestamos.prestamos p SET observacion=$2,
              id_estado_prestamo=(SELECT id_estado_prestamo FROM prestamos.estados_prestamo WHERE nombre=$3)
            WHERE id_prestamo=$1 AND EXISTS(SELECT 1 FROM prestamos.estados_prestamo WHERE nombre=$3)
            """);
        command.Parameters.AddWithValue(id); command.Parameters.AddWithValue((object?)request.Observacion ?? DBNull.Value);
        command.Parameters.AddWithValue(request.Estado.ToUpperInvariant()); return await command.ExecuteNonQueryAsync() > 0;
    }

    private static PrestamoDto Read(NpgsqlDataReader r) => new(r.GetInt32(0),r.GetInt32(1),r.GetString(2),r.GetString(3),r.GetString(4),r.GetString(5),r.GetDecimal(6),
        r.IsDBNull(7)?null:r.GetDecimal(7),r.IsDBNull(8)?null:r.GetInt32(8),r.IsDBNull(9)?null:r.GetDecimal(9),r.IsDBNull(10)?null:r.GetDecimal(10),
        r.IsDBNull(11)?null:r.GetDecimal(11),r.GetFieldValue<DateOnly>(12),r.IsDBNull(13)?null:r.GetFieldValue<DateOnly>(13),
        r.IsDBNull(14)?null:r.GetString(14),r.GetDecimal(15),r.GetDecimal(16),r.GetDecimal(17),r.GetDecimal(18),
        r.IsDBNull(19)?null:r.GetInt32(19),r.IsDBNull(20)?null:r.GetDecimal(20),r.IsDBNull(21)?null:r.GetDecimal(21));
}
