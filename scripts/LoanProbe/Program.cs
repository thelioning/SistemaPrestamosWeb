using Npgsql;
using SistemaPrestamos.Api.Services;

var connection = Environment.GetEnvironmentVariable("PROBE_CONNECTION") ?? throw new InvalidOperationException("Missing connection");
await using var source = NpgsqlDataSource.Create(connection);
var repository = new PrestamoRepository(source);
var loans = await repository.ListAsync(null, null, null);
Console.WriteLine($"LOANS_OK={loans.Count}");
var eligible = await repository.GetEligibleRenewalsAsync();
Console.WriteLine($"RENEWALS_OK={eligible.Count}");
