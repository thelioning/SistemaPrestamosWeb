using Npgsql;
namespace SistemaPrestamos.Api.Services;

public sealed record PrestamoCobroDto(int Id,string Cliente,string Tipo,string Estado,decimal MontoPrestado,decimal SaldoPendiente,decimal? Cuota,decimal? Redito,decimal? CapitalPendiente,string Frecuencia);
public sealed record CuotaCobroDto(int Numero,DateOnly Vencimiento,decimal Programado,decimal Pagado,decimal Pendiente,string Estado);
public sealed record PagoDto(int Id,int PrestamoId,string Cliente,string TipoPrestamo,string TipoPago,DateOnly Fecha,decimal Monto,string Estado,string? Observacion,string? Recibo,string? MotivoAnulacion,bool PuedeAnular);
public sealed record RegistrarPagoRequest(int PrestamoId,string TipoPago,int? NumeroCuota,decimal? Monto,decimal? MontoRedito,decimal? MontoCapital,DateOnly Fecha,string? Observacion);
public sealed record PagoConfirmacionDto(int PagoId,string NumeroRecibo,decimal Monto,DateOnly Fecha);
public sealed record AnularPagoRequest(string Motivo);
public sealed record AnulacionPagoDto(int PagoId,string Estado,string Mensaje);

public sealed class PagoRepository(NpgsqlDataSource dataSource)
{
 public async Task<List<PrestamoCobroDto>> GetLoansAsync(){await using var c=dataSource.CreateCommand("""
  SELECT id_prestamo,cliente,tipo_prestamo,estado,monto_prestado,saldo_pendiente,cuota,monto_redito,capital_pendiente,frecuencia
  FROM prestamos.vw_prestamos_general WHERE estado IN('ACTIVO','ATRASADO') ORDER BY cliente,id_prestamo
  """);var r=new List<PrestamoCobroDto>();await using var x=await c.ExecuteReaderAsync();while(await x.ReadAsync())r.Add(new(x.GetInt32(0),x.GetString(1),x.GetString(2),x.GetString(3),x.GetDecimal(4),x.GetDecimal(5),x.IsDBNull(6)?null:x.GetDecimal(6),x.IsDBNull(7)?null:x.GetDecimal(7),x.IsDBNull(8)?null:x.GetDecimal(8),x.GetString(9)));return r;}
 public async Task<List<CuotaCobroDto>> GetInstallmentsAsync(int id){await using var c=dataSource.CreateCommand("SELECT numero_cuota,fecha_vencimiento,monto_programado,monto_pagado,monto_programado-monto_pagado,estado FROM prestamos.plan_pagos WHERE id_prestamo=$1 AND monto_pagado<monto_programado ORDER BY numero_cuota");c.Parameters.AddWithValue(id);var r=new List<CuotaCobroDto>();await using var x=await c.ExecuteReaderAsync();while(await x.ReadAsync())r.Add(new(x.GetInt32(0),x.GetFieldValue<DateOnly>(1),x.GetDecimal(2),x.GetDecimal(3),x.GetDecimal(4),x.GetString(5)));return r;}
 public async Task<List<PagoDto>> ListAsync(int limit=50){await using var c=dataSource.CreateCommand("""
  SELECT pg.id_pago,pg.id_prestamo,c.nombre,tp.nombre,tpg.nombre,pg.fecha_pago,pg.monto_pagado,pg.estado,pg.observacion,r.numero_recibo,pg.motivo_anulacion,
         pg.estado='APLICADO' AND pg.id_pago=(SELECT max(x.id_pago) FROM prestamos.pagos x WHERE x.id_prestamo=pg.id_prestamo AND x.estado='APLICADO')
  FROM prestamos.pagos pg JOIN prestamos.prestamos p ON p.id_prestamo=pg.id_prestamo JOIN prestamos.cliente c ON c.id_cliente=p.id_cliente
  JOIN prestamos.tipos_prestamo tp ON tp.id_tipo_prestamos=p.id_tipo_prestamos JOIN prestamos.tipos_pago tpg ON tpg.id_tipo_pago=pg.id_tipo_pago
  LEFT JOIN prestamos.recibos_pago r ON r.id_pago=pg.id_pago ORDER BY pg.id_pago DESC LIMIT $1
  """);c.Parameters.AddWithValue(limit);var list=new List<PagoDto>();await using var x=await c.ExecuteReaderAsync();while(await x.ReadAsync())list.Add(new(x.GetInt32(0),x.GetInt32(1),x.GetString(2),x.GetString(3),x.GetString(4),x.GetFieldValue<DateOnly>(5),x.GetDecimal(6),x.GetString(7),x.IsDBNull(8)?null:x.GetString(8),x.IsDBNull(9)?null:x.GetString(9),x.IsDBNull(10)?null:x.GetString(10),x.GetBoolean(11)));return list;}
 public async Task<PagoConfirmacionDto> RegisterAsync(RegistrarPagoRequest q){var type=q.TipoPago.ToUpperInvariant();string sql=type switch{"CUOTA_SAN"=>"SELECT prestamos.registrar_pago_san($1,$2,$3,$4,$5)","REDITO"=>"SELECT prestamos.registrar_pago_redito($1,$2,$3,$4)","ABONO_CAPITAL"=>"SELECT prestamos.registrar_abono_capital($1,$2,$3,$4)","MIXTO"=>"SELECT prestamos.registrar_pago_mixto($1,$2,$3,$4,$5)",_=>throw new ArgumentException("Tipo de pago inválido.")};
  await using var connection=await dataSource.OpenConnectionAsync();await using var transaction=await connection.BeginTransactionAsync();await using var c=new NpgsqlCommand(sql,connection,transaction);c.Parameters.AddWithValue(q.PrestamoId);
  if(type=="CUOTA_SAN"){c.Parameters.AddWithValue(q.NumeroCuota!.Value);c.Parameters.AddWithValue(q.Monto!.Value);}
  else if(type is "REDITO" or "ABONO_CAPITAL")c.Parameters.AddWithValue(q.Monto!.Value);
  else{c.Parameters.AddWithValue(q.MontoRedito!.Value);c.Parameters.AddWithValue(q.MontoCapital!.Value);}
  c.Parameters.AddWithValue(q.Fecha);c.Parameters.AddWithValue((object?)q.Observacion??DBNull.Value);var id=(int)(await c.ExecuteScalarAsync())!;
  if(type=="CUOTA_SAN"){await using var link=new NpgsqlCommand("UPDATE prestamos.pagos SET numero_cuota=$2 WHERE id_pago=$1",connection,transaction);link.Parameters.AddWithValue(id);link.Parameters.AddWithValue(q.NumeroCuota!.Value);await link.ExecuteNonQueryAsync();}
  await using var receipt=new NpgsqlCommand("SELECT numero_recibo,monto_pagado,fecha_pago FROM prestamos.recibos_pago r JOIN prestamos.pagos p ON p.id_pago=r.id_pago WHERE p.id_pago=$1",connection,transaction);receipt.Parameters.AddWithValue(id);await using var x=await receipt.ExecuteReaderAsync();await x.ReadAsync();var result=new PagoConfirmacionDto(id,x.GetString(0),x.GetDecimal(1),x.GetFieldValue<DateOnly>(2));await x.DisposeAsync();await transaction.CommitAsync();return result;}
 public async Task<AnulacionPagoDto> AnnulAsync(int id,string motivo,string usuario){await using var c=dataSource.CreateCommand("SELECT prestamos.anular_pago($1,$2,$3)");c.Parameters.AddWithValue(id);c.Parameters.AddWithValue(motivo);c.Parameters.AddWithValue(usuario);await c.ExecuteScalarAsync();return new(id,"ANULADO","El pago fue anulado y los balances fueron restaurados.");}
}
