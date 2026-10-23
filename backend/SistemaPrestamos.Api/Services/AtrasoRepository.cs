using Npgsql;
namespace SistemaPrestamos.Api.Services;

public sealed record ResumenAtrasosDto(long ClientesAtrasados,long PrestamosAtrasados,long CuotasVencidas,decimal TotalVencido,int MaximoDiasAtraso);
public sealed record ClienteAtrasadoDto(int ClienteId,string Cliente,string? Telefono,long Prestamos,long CuotasVencidas,decimal TotalVencido,int DiasAtraso,DateOnly PrimerVencimiento,int PrestamoId);
public sealed record ControlAtrasosDto(ResumenAtrasosDto Resumen,List<ClienteAtrasadoDto> Clientes);

public sealed class AtrasoRepository(NpgsqlDataSource source)
{
 private const string ObligacionesSql = """
 WITH san AS (
   SELECT c.id_cliente,c.nombre cliente,c.telefono,p.id_prestamo,
          COUNT(*)::bigint cuotas_vencidas,
          SUM(pp.monto_programado-pp.monto_pagado)::numeric total_vencido,
          MIN(pp.fecha_vencimiento) primer_vencimiento,
          (current_date-MIN(pp.fecha_vencimiento))::int dias_atraso
   FROM prestamos.plan_pagos pp
   JOIN prestamos.prestamos p ON p.id_prestamo=pp.id_prestamo
   JOIN prestamos.tipos_prestamo tp ON tp.id_tipo_prestamos=p.id_tipo_prestamos
   JOIN prestamos.estados_prestamo ep ON ep.id_estado_prestamo=p.id_estado_prestamo
   JOIN prestamos.cliente c ON c.id_cliente=p.id_cliente
   WHERE tp.nombre='SAN'
     AND pp.fecha_vencimiento<current_date
     AND pp.monto_pagado<pp.monto_programado
     AND ep.nombre IN ('ACTIVO','ATRASADO')
   GROUP BY c.id_cliente,c.nombre,c.telefono,p.id_prestamo
 ),
 redito_base AS (
   SELECT c.id_cliente,c.nombre cliente,c.telefono,p.id_prestamo,p.fecha_inicio,p.monto_redito,f.dias,
          MAX(pg.fecha_pago) FILTER(WHERE pg.estado='APLICADO' AND tpg.nombre='REDITO') ultimo_pago,
          COALESCE(SUM(pg.monto_pagado) FILTER(WHERE pg.estado='APLICADO' AND tpg.nombre='REDITO'),0) pagado_redito
   FROM prestamos.prestamos p
   JOIN prestamos.tipos_prestamo tp ON tp.id_tipo_prestamos=p.id_tipo_prestamos
   JOIN prestamos.estados_prestamo ep ON ep.id_estado_prestamo=p.id_estado_prestamo
   JOIN prestamos.frecuencias_pago f ON f.id_frecuencia=p.id_frecuencia
   JOIN prestamos.cliente c ON c.id_cliente=p.id_cliente
   LEFT JOIN prestamos.pagos pg ON pg.id_prestamo=p.id_prestamo
   LEFT JOIN prestamos.tipos_pago tpg ON tpg.id_tipo_pago=pg.id_tipo_pago
   WHERE tp.nombre='REDITO' AND ep.nombre IN ('ACTIVO','ATRASADO')
   GROUP BY c.id_cliente,c.nombre,c.telefono,p.id_prestamo,p.fecha_inicio,p.monto_redito,f.dias
 ),
 redito AS (
   SELECT id_cliente,cliente,telefono,id_prestamo,
          CEIL(GREATEST((GREATEST(((current_date-fecha_inicio)/NULLIF(dias,0))::int,0)*monto_redito)-pagado_redito,0)/NULLIF(monto_redito,0))::bigint cuotas_vencidas,
          GREATEST((GREATEST(((current_date-fecha_inicio)/NULLIF(dias,0))::int,0)*monto_redito)-pagado_redito,0)::numeric total_vencido,
          (fecha_inicio+(((FLOOR(pagado_redito/NULLIF(monto_redito,0)))::int+1)*dias))::date primer_vencimiento,
          GREATEST((current_date-(fecha_inicio+(((FLOOR(pagado_redito/NULLIF(monto_redito,0)))::int+1)*dias)))::int,0) dias_atraso
   FROM redito_base
   WHERE GREATEST((GREATEST(((current_date-fecha_inicio)/NULLIF(dias,0))::int,0)*monto_redito)-pagado_redito,0)>0
 ),
 obligaciones AS (
   SELECT * FROM san
   UNION ALL
   SELECT * FROM redito
 )
 """;

 public async Task<ControlAtrasosDto> GetAsync()
 {
  await using var summary=source.CreateCommand(ObligacionesSql+"""
   SELECT COUNT(DISTINCT id_cliente),COUNT(DISTINCT id_prestamo),COALESCE(SUM(cuotas_vencidas),0),
          COALESCE(SUM(total_vencido),0),COALESCE(MAX(dias_atraso),0)
   FROM obligaciones
   """);
  await using var sr=await summary.ExecuteReaderAsync();await sr.ReadAsync();
  var totals=new ResumenAtrasosDto(sr.GetInt64(0),sr.GetInt64(1),sr.GetInt64(2),sr.GetDecimal(3),sr.GetInt32(4));

  await using var command=source.CreateCommand(ObligacionesSql+"""
   SELECT id_cliente,cliente,telefono,COUNT(DISTINCT id_prestamo),SUM(cuotas_vencidas),
          SUM(total_vencido),MAX(dias_atraso),MIN(primer_vencimiento),MIN(id_prestamo)
   FROM obligaciones
   GROUP BY id_cliente,cliente,telefono
   ORDER BY MAX(dias_atraso) DESC,SUM(total_vencido) DESC
   """);
  var clients=new List<ClienteAtrasadoDto>();
  await using var reader=await command.ExecuteReaderAsync();
  while(await reader.ReadAsync())clients.Add(new(reader.GetInt32(0),reader.GetString(1),reader.IsDBNull(2)?null:reader.GetString(2),reader.GetInt64(3),reader.GetInt64(4),reader.GetDecimal(5),reader.GetInt32(6),reader.GetFieldValue<DateOnly>(7),reader.GetInt32(8)));
  return new(totals,clients);
 }
}
