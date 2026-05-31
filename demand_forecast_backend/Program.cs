using Microsoft.EntityFrameworkCore;
using DemandForecastBackend.Data;
using DemandForecastBackend.Services;

var builder = WebApplication.CreateBuilder(args);

// ── Services ─────────────────────────────────────────────
builder.Services.AddControllers()
    .AddJsonOptions(opt =>
        opt.JsonSerializerOptions.PropertyNamingPolicy =
            System.Text.Json.JsonNamingPolicy.CamelCase);
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// EF Core — SQL Server
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection")));

// Business services
builder.Services.AddScoped<DatabaseService>();
builder.Services.AddScoped<ForecastService>();
builder.Services.AddScoped<ExcelExportService>();
builder.Services.AddScoped<PythonRunnerService>();
builder.Services.AddScoped<CsvImportService>();
builder.Services.AddScoped<ExcelImportService>();

// CORS — allow Flutter desktop app on any localhost port
builder.Services.AddCors(opt =>
    opt.AddDefaultPolicy(policy =>
        policy.SetIsOriginAllowed(origin =>
                new Uri(origin).Host == "localhost")
              .AllowAnyHeader()
              .AllowAnyMethod()));

var app = builder.Build();

// ── Middleware ────────────────────────────────────────────
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseCors();
app.MapControllers();

// ── Auto-create DB tables on startup ─────────────────────
var startupLogger = app.Services.GetRequiredService<ILogger<Program>>();
try
{
    using var scope = app.Services.CreateScope();
    var ctx = scope.ServiceProvider.GetRequiredService<AppDbContext>();

    // EnsureCreated creates missing tables but won't alter existing ones.
    // If ForecastJobs/ForecastResults tables are missing, this will create them.
    ctx.Database.EnsureCreated();

    // Verify ForecastJobs table exists with new schema (including JobId)
    try
    {
        ctx.ForecastJobs.Count(); // will throw if table doesn't exist
        var count = ctx.ForecastResults.Select(r => r.MonthlyBreakdown).FirstOrDefault(); // will throw if column doesn't exist
        // Check new JobId column exists
        var jobIdCheck = ctx.ForecastJobs.Select(j => j.JobId).FirstOrDefault();
    }
    catch
    {
        startupLogger.LogWarning("[Startup] ForecastJobs or ForecastResults table missing / schema outdated — recreating schema...");
        // Drop and recreate only if the table is genuinely missing or outdated
        ctx.Database.EnsureDeleted();
        ctx.Database.EnsureCreated();
        startupLogger.LogInformation("[Startup] Schema recreated successfully.");
    }

    startupLogger.LogInformation("[Startup] Database tables ensured.");
}
catch (Exception dbEx)
{
    startupLogger.LogWarning("[Startup] Could not connect to database on startup: {Error}", dbEx.Message);
    startupLogger.LogWarning("[Startup] Backend will still run. Check your DefaultConnection string in appsettings.json.");
}

app.Run();
