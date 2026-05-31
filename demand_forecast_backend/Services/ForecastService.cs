using Microsoft.EntityFrameworkCore;
using DemandForecastBackend.Data;
using DemandForecastBackend.DTOs;
using DemandForecastBackend.Models;
using Microsoft.Data.SqlClient;
using System.Text.Json;

namespace DemandForecastBackend.Services;

public class ForecastService
{
    private readonly AppDbContext _db;
    private readonly PythonRunnerService _python;
    private readonly ILogger<ForecastService> _logger;
    private readonly IServiceScopeFactory _scopeFactory;

    public ForecastService(
        AppDbContext db,
        PythonRunnerService python,
        ILogger<ForecastService> logger,
        IServiceScopeFactory scopeFactory)
    {
        _db = db;
        _python = python;
        _logger = logger;
        _scopeFactory = scopeFactory;
    }

    // ── Filter Options ───────────────────────────────────────────────────────

    public async Task<object> GetFiltersAsync()
    {
        var industries = new List<string> { "All" };
        var companies  = new List<string> { "All" };

        var minDateQuery = await _db.DatasetRecords.Select(r => (DateTime?)r.orderDate).ToListAsync();
        var minDate = minDateQuery.Min();
        var maxYear = minDate.HasValue
            ? Math.Min((int)Math.Floor((DateTime.UtcNow - minDate.Value).TotalDays / 365.0), 10)
            : 3;

        var lookbackOptions = Enumerable.Range(1, Math.Max(maxYear, 1))
            .Select(y => $"Last {y} Year{(y > 1 ? "s" : "")}")
            .ToList();

        return new
        {
            industries,
            companies,
            lookbackOptions,
            modelOptions    = new[] { "ARIMA", "Linear Regression", "Exp Smoothing", "Prophet", "Croston" },
            periodOptions   = new[] { "1 Year", "2 Years" }
        };
    }

    // ── Category / Item Loading ──────────────────────────────────────────────

    public async Task<(bool success, List<CategoryDto> categories, int totalCount, string message)> LoadForecastDataAsync(LoadForecastDataRequest req)
    {
        try
        {
            var query = _db.DatasetRecords.AsNoTracking();

            if (!string.IsNullOrWhiteSpace(req.SearchQuery))
            {
                var lowerSearch = req.SearchQuery.ToLower();
                query = query.Where(q => q.ITEMDESC.ToLower().Contains(lowerSearch) || q.ITEMNO.ToLower().Contains(lowerSearch));
            }

            var categoryQuery = query.Select(q => q.ITEMDESC).Distinct();
            var totalCount = await categoryQuery.CountAsync();

            var pagedCategories = await categoryQuery
                .OrderBy(c => c)
                .Skip((req.Page - 1) * req.PageSize)
                .Take(req.PageSize)
                .ToListAsync();

            if (pagedCategories.Count == 0)
                return (true, new List<CategoryDto>(), totalCount, "Success");

            var dtos = pagedCategories.Select(cat => new CategoryDto
            {
                Id   = cat,
                Name = cat,
                Items = new List<ItemDto>()
            }).ToList();

            return (true, dtos, totalCount, "Success");
        }
        catch (Exception ex)
        {
            return (false, new List<CategoryDto>(), 0, ex.Message);
        }
    }

    public async Task<(bool success, List<ItemDto> items, int totalCount, string message)> LoadCategoryItemsAsync(LoadCategoryItemsRequest req)
    {
        try
        {
            var query = _db.DatasetRecords
                .Where(r => r.ITEMDESC == req.CategoryId)
                .Select(r => r.ITEMNO)
                .Distinct();

            if (!string.IsNullOrWhiteSpace(req.SearchQuery))
            {
                var lowerSearch = req.SearchQuery.ToLower();
                query = query.Where(itemNo => itemNo.ToLower().Contains(lowerSearch));
            }

            var totalCount = await query.CountAsync();

            var pagedItems = await query
                .OrderBy(itemNo => itemNo)
                .Skip(req.Skip)
                .Take(req.PageSize)
                .ToListAsync();

            var dtos = pagedItems.Select(itemNo => new ItemDto
            {
                Id = itemNo,
                Name = itemNo,
                CategoryId = req.CategoryId
            }).ToList();

            return (true, dtos, totalCount, "Success");
        }
        catch (Exception ex)
        {
            return (false, new List<ItemDto>(), 0, ex.Message);
        }
    }

    // ── Job ID Generation ────────────────────────────────────────────────────

    private static readonly Random _rng = new();

    private async Task<string> GenerateUniqueJobIdAsync(AppDbContext db)
    {
        string jobId;
        do
        {
            var num = _rng.Next(100, 1000);
            jobId = $"JOB-{num}";
        } while (await db.ForecastJobs.AnyAsync(j => j.JobId == jobId));

        return jobId;
    }

    // ── Async Job Start (fire-and-forget) ────────────────────────────────────

    /// <summary>
    /// Creates a "Pending" job record immediately and runs the forecast in the background.
    /// Returns the JobId right away without waiting for the forecast to finish.
    /// </summary>
    public async Task<(bool success, string jobId, string message)> StartForecastJobAsync(PreviewRequest req)
    {
        try
        {
            var jobId = await GenerateUniqueJobIdAsync(_db);

            var selectedItemsJson   = JsonSerializer.Serialize(req.ItemIds);
            var selectedCatsJson    = JsonSerializer.Serialize(req.CategoryIds);

            var job = new ForecastJob
            {
                JobId              = jobId,
                JobName            = req.JobName,
                Model              = req.Model,
                Lookback           = req.Lookback,
                Period             = req.Period,
                SelectedCategories = selectedCatsJson,
                SelectedItems      = selectedItemsJson,
                Status             = "Pending",
                CreatedAt          = DateTime.UtcNow
            };

            _db.ForecastJobs.Add(job);
            await _db.SaveChangesAsync();

            // Fire and forget — run forecast in background using a new DI scope
            var dbJobId = job.Id;
            _ = Task.Run(async () =>
            {
                await RunForecastInBackgroundAsync(dbJobId, req);
            });

            return (true, jobId, "Job created successfully.");
        }
        catch (Exception ex)
        {
            var inner = ex.InnerException?.Message ?? ex.Message;
            return (false, string.Empty, inner);
        }
    }

    /// <summary>
    /// Background task that performs the actual forecasting and updates job status.
    /// Uses IServiceScopeFactory to get a fresh DbContext (required in background threads).
    /// </summary>
    private async Task RunForecastInBackgroundAsync(int dbJobId, PreviewRequest req)
    {
        using var scope = _scopeFactory.CreateScope();
        var db     = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var python = scope.ServiceProvider.GetRequiredService<PythonRunnerService>();
        var logger = scope.ServiceProvider.GetRequiredService<ILogger<ForecastService>>();

        try
        {
            // 1. Mark job as Processing
            var job = await db.ForecastJobs.FindAsync(dbJobId);
            if (job == null)
            {
                logger.LogWarning("[Background] Job {Id} not found.", dbJobId);
                return;
            }
            job.Status = "Processing";
            await db.SaveChangesAsync();

            // 2. Collect records
            var recordsQuery = db.DatasetRecords.AsQueryable();

            if (req.ItemIds.Any())
            {
                var itemNos = req.ItemIds.ToList();
                recordsQuery = recordsQuery.Where(r => itemNos.Contains(r.ITEMNO));
            }
            else if (req.CategoryIds.Any())
            {
                var catIds = req.CategoryIds.ToList();
                recordsQuery = recordsQuery.Where(r => catIds.Contains(r.ITEMDESC));
            }
            else
            {
                job.Status = "Failed";
                await db.SaveChangesAsync();
                return;
            }

            var records = await recordsQuery.ToListAsync();
            var items   = records.GroupBy(r => new { r.ITEMDESC, r.ITEMNO }).ToList();

            int lookbackYears  = ExtractLookbackYears(req.Lookback);
            var latestSaleDate = records.Select(s => s.orderDate).DefaultIfEmpty(DateTime.UtcNow).Max();
            var cutoff         = latestSaleDate.AddYears(-lookbackYears);
            int forecastPeriods = ExtractPeriodYears(req.Period);

            var payload = new
            {
                items = items.Select(item => new
                {
                    itemId       = item.Key.ITEMNO,
                    itemName     = item.Key.ITEMNO,
                    categoryId   = item.Key.ITEMDESC,
                    categoryName = item.Key.ITEMDESC,
                    history = item
                        .Where(s => s.orderDate >= cutoff)
                        .OrderBy(s => s.orderDate)
                        .Select(s => new { date = s.orderDate.ToString("yyyy-MM"), quantity = s.quantity })
                        .ToList()
                }).ToList(),
                model           = req.Model,
                forecastPeriods = forecastPeriods
            };

            var rawResults = await python.RunForecastAsync(payload);

            // 3. Save results and mark Completed
            job = await db.ForecastJobs.FindAsync(dbJobId);
            if (job == null) return;

            foreach (var r in rawResults)
            {
                string Safe(string key) => r.ContainsKey(key) ? (r[key].ToString() ?? "") : "";
                double SafeDouble(string key) => r.ContainsKey(key) && r[key] is JsonElement je ? je.GetDouble() : 0.0;
                string SafeJson(string key) => r.ContainsKey(key) && r[key] is JsonElement je ? je.GetRawText() : "[]";

                var catId   = Safe("categoryId");
                var catName = Safe("categoryName");
                var itmId   = Safe("itemId");
                var itmName = Safe("itemName");

                db.ForecastResults.Add(new ForecastResult
                {
                    ForecastJobId      = dbJobId,
                    CategoryId         = catId.Length   > 500 ? catId.Substring(0, 500)   : catId,
                    CategoryName       = catName.Length > 500 ? catName.Substring(0, 500) : catName,
                    ItemId             = itmId.Length   > 500 ? itmId.Substring(0, 500)   : itmId,
                    ItemName           = itmName.Length > 500 ? itmName.Substring(0, 500) : itmName,
                    ForecastYear       = Safe("forecastYear"),
                    Model              = req.Model,
                    AccuracyPercent    = SafeDouble("accuracyPercent"),
                    ForecastedQuantity = SafeDouble("forecastedQuantity"),
                    MonthlyBreakdown   = SafeJson("monthlyBreakdown")
                });
            }

            job.Status = "Completed";
            await db.SaveChangesAsync();
            logger.LogInformation("[Background] Job {JobId} Completed.", job.JobId);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "[Background] Job {Id} Failed.", dbJobId);
            try
            {
                using var failScope = _scopeFactory.CreateScope();
                var failDb = failScope.ServiceProvider.GetRequiredService<AppDbContext>();
                var failJob = await failDb.ForecastJobs.FindAsync(dbJobId);
                if (failJob != null)
                {
                    failJob.Status = "Failed";
                    await failDb.SaveChangesAsync();
                }
            }
            catch { /* best-effort */ }
        }
    }

    // ── Get Jobs (Dashboard) ─────────────────────────────────────────────────

    public async Task<List<ForecastJobDto>> GetJobsAsync()
    {
        var jobs = await _db.ForecastJobs
            .OrderByDescending(j => j.CreatedAt)
            .ToListAsync();

        return jobs.Select(j => new ForecastJobDto
        {
            Id                 = j.Id,
            JobId              = j.JobId,
            JobName            = j.JobName,
            Model              = j.Model,
            Lookback           = j.Lookback,
            Period             = j.Period,
            SelectedCategories = j.SelectedCategories,
            SelectedItems      = j.SelectedItems,
            Status             = j.Status,
            CreatedAt          = j.CreatedAt,
            Results            = new List<ForecastResultDto>() // not loaded eagerly on list
        }).ToList();
    }

    // ── Get Single Job Results (Preview) ─────────────────────────────────────

    public async Task<(bool success, ForecastJobDto? job, string message)> GetJobResultsAsync(string jobId)
    {
        try
        {
            var job = await _db.ForecastJobs
                .Include(j => j.Results)
                .FirstOrDefaultAsync(j => j.JobId == jobId);

            if (job == null)
                return (false, null, "Job not found.");

            var dto = new ForecastJobDto
            {
                Id                 = job.Id,
                JobId              = job.JobId,
                JobName            = job.JobName,
                Model              = job.Model,
                Lookback           = job.Lookback,
                Period             = job.Period,
                SelectedCategories = job.SelectedCategories,
                SelectedItems      = job.SelectedItems,
                Status             = job.Status,
                CreatedAt          = job.CreatedAt,
                Results = job.Results.Select(r => new ForecastResultDto
                {
                    CategoryId         = r.CategoryId,
                    CategoryName       = r.CategoryName,
                    ItemId             = r.ItemId,
                    ItemName           = r.ItemName,
                    ForecastYear       = r.ForecastYear,
                    Model              = r.Model,
                    AccuracyPercent    = r.AccuracyPercent,
                    ForecastedQuantity = r.ForecastedQuantity,
                    MonthlyBreakdown   = r.MonthlyBreakdown
                }).ToList()
            };

            return (true, dto, "Success");
        }
        catch (Exception ex)
        {
            return (false, null, ex.Message);
        }
    }

    // ── Dataset Import ───────────────────────────────────────────────────────

    public async Task LoadDatasetFromSourceAsync(string sourceConnStr)
    {
        _logger.LogInformation($"Connecting to source database: {sourceConnStr}");

        var builder = new SqlConnectionStringBuilder(sourceConnStr);
        if (builder.InitialCatalog.Equals("DemandForecastDB", StringComparison.OrdinalIgnoreCase) &&
            (builder.DataSource.Contains("localhost") || builder.DataSource.Contains("127.0.0.1") || builder.DataSource.Contains("(local)")))
        {
            _logger.LogWarning("Source database is the same as destination. Skipping import.");
            return;
        }

        using var sourceConn = new SqlConnection(sourceConnStr);
        await sourceConn.OpenAsync();

        var sqlDetect = @"
            SELECT t.name AS TableName, c.name AS ColumnName
            FROM sys.tables t
            JOIN sys.columns c ON c.object_id = t.object_id
            WHERE t.is_ms_shipped = 0
            ORDER BY t.name, c.column_id";

        var tableColumns = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        using (var cmdDetect = new SqlCommand(sqlDetect, sourceConn))
        {
            using var reader = await cmdDetect.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                var tbl = reader.GetString(0);
                var col = reader.GetString(1);
                if (!tableColumns.ContainsKey(tbl)) tableColumns[tbl] = new();
                tableColumns[tbl].Add(col);
            }
        }

        foreach (var tc in tableColumns)
            _logger.LogInformation($"[Scan] Found table: {tc.Key}. Columns: {string.Join(", ", tc.Value)}");

        string? flatTable = null;
        foreach (var (tbl, cols) in tableColumns)
        {
            bool hasDate     = cols.Any(c => c.Contains("Date",     StringComparison.OrdinalIgnoreCase) || c.Contains("Month", StringComparison.OrdinalIgnoreCase));
            bool hasItemDesc = cols.Any(c => c.Contains("ITEMDESC", StringComparison.OrdinalIgnoreCase) || c.Contains("Category", StringComparison.OrdinalIgnoreCase) || c.Contains("cat", StringComparison.OrdinalIgnoreCase));
            bool hasItemNo   = cols.Any(c => c.Contains("ITEMNO",   StringComparison.OrdinalIgnoreCase) || c.Contains("Item", StringComparison.OrdinalIgnoreCase));
            bool hasQty      = cols.Any(c => c.Contains("Quantity", StringComparison.OrdinalIgnoreCase) || c.Contains("Qty", StringComparison.OrdinalIgnoreCase));

            _logger.LogInformation($"[Eval] Table {tbl} -> Date:{hasDate}, Desc:{hasItemDesc}, No:{hasItemNo}, Qty:{hasQty}");

            if (hasDate && hasItemDesc && hasItemNo && hasQty)
            {
                flatTable = tbl;
                break;
            }
        }

        if (flatTable == null)
            throw new Exception("No flat table found in the selected database.");

        _logger.LogInformation($"Detected flat table: {flatTable}. Reading data...");

        var newRecords = new List<DatasetRecord>();
        var safeName   = $"[{flatTable.Replace("]", "]]")}]";

        using (var cmdRead = new SqlCommand($"SELECT * FROM {safeName}", sourceConn))
        {
            using var reader = await cmdRead.ExecuteReaderAsync();
            var schema = Enumerable.Range(0, reader.FieldCount)
                .ToDictionary(i => reader.GetName(i), i => i, StringComparer.OrdinalIgnoreCase);

            int? GetIdx(string key) => schema.TryGetValue(key, out var idx) ? idx : (int?)null;
            int? dateIdx = GetIdx("orderDate") ?? GetIdx("Date") ?? schema.Keys.Select(k => (int?)schema[k]).FirstOrDefault(i => reader.GetName(i!.Value).Contains("date", StringComparison.OrdinalIgnoreCase));
            int? descIdx = GetIdx("ITEMDESC")  ?? GetIdx("Category") ?? schema.Keys.Select(k => (int?)schema[k]).FirstOrDefault(i => reader.GetName(i!.Value).Contains("cat", StringComparison.OrdinalIgnoreCase));
            int? noIdx   = GetIdx("ITEMNO")    ?? GetIdx("Item")     ?? schema.Keys.Select(k => (int?)schema[k]).FirstOrDefault(i => reader.GetName(i!.Value).Contains("item", StringComparison.OrdinalIgnoreCase));
            int? qtyIdx  = GetIdx("quantity")  ?? GetIdx("Qty")      ?? schema.Keys.Select(k => (int?)schema[k]).FirstOrDefault(i => reader.GetName(i!.Value).Contains("qty", StringComparison.OrdinalIgnoreCase));

            if (dateIdx == null || descIdx == null || noIdx == null || qtyIdx == null)
                throw new Exception($"Failed to map columns in table {flatTable}.");

            while (await reader.ReadAsync())
            {
                var dateVal = reader.IsDBNull(dateIdx.Value) ? (object?)null : reader.GetValue(dateIdx.Value);
                var descStr = reader.IsDBNull(descIdx.Value) ? "" : reader.GetValue(descIdx.Value)?.ToString() ?? "";
                var noStr   = reader.IsDBNull(noIdx.Value)   ? "" : reader.GetValue(noIdx.Value)?.ToString()   ?? "";
                var qtyVal  = reader.IsDBNull(qtyIdx.Value)  ? (object?)null : reader.GetValue(qtyIdx.Value);

                if (dateVal == null || qtyVal == null || string.IsNullOrWhiteSpace(descStr) || string.IsNullOrWhiteSpace(noStr)) continue;
                if (!DateTime.TryParse(dateVal.ToString(), out DateTime dt)) continue;
                if (!double.TryParse(qtyVal.ToString(), out double qty)) continue;

                newRecords.Add(new DatasetRecord
                {
                    orderDate = dt,
                    ITEMDESC  = descStr,
                    ITEMNO    = noStr,
                    quantity  = qty
                });
            }
        }

        _db.DatasetRecords.RemoveRange(_db.DatasetRecords);
        await _db.SaveChangesAsync();

        _db.DatasetRecords.AddRange(newRecords);
        await _db.SaveChangesAsync();

        _logger.LogInformation($"Successfully loaded {newRecords.Count} records from table {flatTable}.");
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private static int ExtractLookbackYears(string lookback)
    {
        if (string.IsNullOrEmpty(lookback)) return 3;
        var parts = lookback.Split(' ');
        return parts.Length > 1 && int.TryParse(parts[1], out var y) ? y : 3;
    }

    private static int ExtractPeriodYears(string period)
    {
        if (string.IsNullOrEmpty(period)) return 1;
        var parts = period.Split(' ');
        return parts.Length > 0 && int.TryParse(parts[0], out var y) ? y : 1;
    }
}
