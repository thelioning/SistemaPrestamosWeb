using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.FileProviders;
using Npgsql;
using QuestPDF.Infrastructure;
using SistemaPrestamos.Api.Services;
QuestPDF.Settings.License=LicenseType.Community;
var cs=Environment.GetEnvironmentVariable("PROBE_CONNECTION")??throw new Exception("Missing connection");
var root=Environment.GetEnvironmentVariable("RECEIPT_ROOT")??Directory.GetCurrentDirectory();
await using var source=NpgsqlDataSource.Create(cs);var repo=new ReciboRepository(source);var clients=await repo.ClientsAsync();var receipts=await repo.ByClientAsync(clients[0].ClienteId);var service=new ReciboPdfService(repo,new Env(root));var path=await service.EnsureAsync(receipts[0].Id);Console.WriteLine(path);
sealed class Env(string root):IWebHostEnvironment{public string ApplicationName{get;set;}="ReceiptProbe";public IFileProvider WebRootFileProvider{get;set;}=new NullFileProvider();public string WebRootPath{get;set;}=root;public string EnvironmentName{get;set;}="Development";public string ContentRootPath{get;set;}=root;public IFileProvider ContentRootFileProvider{get;set;}=new PhysicalFileProvider(root);}
