using Npgsql;
namespace SistemaPrestamos.Api.Services;

public sealed record CarteraFilaDto(int PrestamoId,int ClienteId,string Cliente,string Tipo,string Estado,decimal MontoPrestado,decimal Pagado,decimal Balance,decimal Vencido,int DiasAtraso);
public sealed record CarteraReporteDto(decimal TotalPrestado,decimal TotalPagado,decimal TotalBalance,decimal TotalVencido,List<CarteraFilaDto> Prestamos);
public sealed record EstadoClienteDto(int Id,string Nombre,string? Documento,string? Telefono,string? Direccion);
public sealed record MovimientoEstadoDto(int Id,int PrestamoId,DateOnly Fecha,string Concepto,decimal Monto,string Estado,string? Recibo,string? Observacion);
public sealed record EstadoCuentaDto(EstadoClienteDto Cliente,decimal TotalPrestado,decimal TotalPagado,decimal Balance,List<CarteraFilaDto> Prestamos,List<MovimientoEstadoDto> Movimientos);

public sealed class ReporteRepository(NpgsqlDataSource source)
{
 public async Task<CarteraReporteDto> CarteraAsync()
 {
  await using var c=source.CreateCommand("""SELECT v.id_prestamo,v.id_cliente,v.cliente,v.tipo_prestamo,v.estado,v.monto_prestado,CASE WHEN v.tipo_prestamo='SAN' THEN v.total_pagado_san ELSE v.total_capital_abonado END,v.saldo_pendiente,COALESCE(a.vencido,0),COALESCE(a.dias,0) FROM prestamos.vw_prestamos_general v LEFT JOIN LATERAL(SELECT SUM(pp.monto_programado-pp.monto_pagado) vencido,MAX(current_date-pp.fecha_vencimiento)::int dias FROM prestamos.plan_pagos pp WHERE pp.id_prestamo=v.id_prestamo AND pp.fecha_vencimiento<current_date AND pp.monto_pagado<pp.monto_programado)a ON true ORDER BY CASE v.estado WHEN 'ATRASADO' THEN 0 WHEN 'ACTIVO' THEN 1 ELSE 2 END,v.cliente,v.id_prestamo""");var rows=new List<CarteraFilaDto>();await using var r=await c.ExecuteReaderAsync();while(await r.ReadAsync())rows.Add(new(r.GetInt32(0),r.GetInt32(1),r.GetString(2),r.GetString(3),r.GetString(4),r.GetDecimal(5),r.GetDecimal(6),r.GetDecimal(7),r.GetDecimal(8),r.GetInt32(9)));return new(rows.Sum(x=>x.MontoPrestado),rows.Sum(x=>x.Pagado),rows.Sum(x=>x.Balance),rows.Sum(x=>x.Vencido),rows);
 }
 public async Task<EstadoCuentaDto?> EstadoCuentaAsync(int clienteId)
 {
  await using var cc=source.CreateCommand("SELECT id_cliente,nombre,documento,telefono,direccion FROM prestamos.cliente WHERE id_cliente=$1");cc.Parameters.AddWithValue(clienteId);await using var cr=await cc.ExecuteReaderAsync();if(!await cr.ReadAsync())return null;var client=new EstadoClienteDto(cr.GetInt32(0),cr.GetString(1),cr.IsDBNull(2)?null:cr.GetString(2),cr.IsDBNull(3)?null:cr.GetString(3),cr.IsDBNull(4)?null:cr.GetString(4));await cr.DisposeAsync();
  var portfolio=await CarteraAsync();var loans=portfolio.Prestamos.Where(x=>x.ClienteId==clienteId).ToList();
  await using var pc=source.CreateCommand("""SELECT pg.id_pago,pg.id_prestamo,pg.fecha_pago,tp.nombre,pg.monto_pagado,pg.estado,r.numero_recibo,pg.observacion FROM prestamos.pagos pg JOIN prestamos.prestamos p ON p.id_prestamo=pg.id_prestamo JOIN prestamos.tipos_pago tp ON tp.id_tipo_pago=pg.id_tipo_pago LEFT JOIN prestamos.recibos_pago r ON r.id_pago=pg.id_pago WHERE p.id_cliente=$1 ORDER BY pg.fecha_pago DESC,pg.id_pago DESC""");pc.Parameters.AddWithValue(clienteId);var payments=new List<MovimientoEstadoDto>();await using var pr=await pc.ExecuteReaderAsync();while(await pr.ReadAsync())payments.Add(new(pr.GetInt32(0),pr.GetInt32(1),pr.GetFieldValue<DateOnly>(2),pr.GetString(3),pr.GetDecimal(4),pr.GetString(5),pr.IsDBNull(6)?null:pr.GetString(6),pr.IsDBNull(7)?null:pr.GetString(7)));
  return new(client,loans.Sum(x=>x.MontoPrestado),loans.Sum(x=>x.Pagado),loans.Sum(x=>x.Balance),loans,payments);
 }
}
