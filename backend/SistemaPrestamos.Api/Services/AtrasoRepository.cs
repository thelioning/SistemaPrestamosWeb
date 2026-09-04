using Npgsql;
namespace SistemaPrestamos.Api.Services;

public sealed record ResumenAtrasosDto(long ClientesAtrasados,long PrestamosAtrasados,long CuotasVencidas,decimal TotalVencido,int MaximoDiasAtraso);
public sealed record ClienteAtrasadoDto(int ClienteId,string Cliente,string? Telefono,long Prestamos,long CuotasVencidas,decimal TotalVencido,int DiasAtraso,DateOnly PrimerVencimiento,int PrestamoId);
public sealed record ControlAtrasosDto(ResumenAtrasosDto Resumen,List<ClienteAtrasadoDto> Clientes);

public sealed class AtrasoRepository(NpgsqlDataSource source)
{
 public async Task<ControlAtrasosDto> GetAsync()
 {
  const string baseWhere="""pp.fecha_vencimiento<current_date AND pp.monto_pagado<pp.monto_programado AND ep.nombre IN ('ACTIVO','ATRASADO')""";
  await using var summary=source.CreateCommand($"""SELECT COUNT(DISTINCT p.id_cliente),COUNT(DISTINCT p.id_prestamo),COUNT(*),COALESCE(SUM(pp.monto_programado-pp.monto_pagado),0),COALESCE(MAX(current_date-pp.fecha_vencimiento),0) FROM prestamos.plan_pagos pp JOIN prestamos.prestamos p ON p.id_prestamo=pp.id_prestamo JOIN prestamos.estados_prestamo ep ON ep.id_estado_prestamo=p.id_estado_prestamo WHERE {baseWhere}""");
  await using var sr=await summary.ExecuteReaderAsync();await sr.ReadAsync();var totals=new ResumenAtrasosDto(sr.GetInt64(0),sr.GetInt64(1),sr.GetInt64(2),sr.GetDecimal(3),sr.GetInt32(4));
  await using var command=source.CreateCommand($"""SELECT c.id_cliente,c.nombre,c.telefono,COUNT(DISTINCT p.id_prestamo),COUNT(*),SUM(pp.monto_programado-pp.monto_pagado),(current_date-MIN(pp.fecha_vencimiento))::int,MIN(pp.fecha_vencimiento),MIN(p.id_prestamo) FROM prestamos.plan_pagos pp JOIN prestamos.prestamos p ON p.id_prestamo=pp.id_prestamo JOIN prestamos.estados_prestamo ep ON ep.id_estado_prestamo=p.id_estado_prestamo JOIN prestamos.cliente c ON c.id_cliente=p.id_cliente WHERE {baseWhere} GROUP BY c.id_cliente,c.nombre,c.telefono ORDER BY (current_date-MIN(pp.fecha_vencimiento)) DESC,SUM(pp.monto_programado-pp.monto_pagado) DESC""");
  var clients=new List<ClienteAtrasadoDto>();await using var reader=await command.ExecuteReaderAsync();while(await reader.ReadAsync())clients.Add(new(reader.GetInt32(0),reader.GetString(1),reader.IsDBNull(2)?null:reader.GetString(2),reader.GetInt64(3),reader.GetInt64(4),reader.GetDecimal(5),reader.GetInt32(6),reader.GetFieldValue<DateOnly>(7),reader.GetInt32(8)));
  return new(totals,clients);
 }
}
