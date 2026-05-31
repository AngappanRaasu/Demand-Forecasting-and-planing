using CsvHelper;
using CsvHelper.Configuration;
using DemandForecastBackend.Data;
using DemandForecastBackend.Models;
using Microsoft.EntityFrameworkCore;
using System.Globalization;

namespace DemandForecastBackend.Services;

public class CsvImportService
{
    private readonly AppDbContext _db;
    private readonly ILogger<CsvImportService> _logger;

    public CsvImportService(AppDbContext db, ILogger<CsvImportService> logger)
    {
        _db = db;
        _logger = logger;
    }

    public async Task<(bool success, string message)> ImportFromStreamAsync(Stream fileStream)
    {
        try
        {
            var config = new CsvConfiguration(CultureInfo.InvariantCulture)
            {
                HasHeaderRecord = true,
                TrimOptions = TrimOptions.Trim,
                MissingFieldFound = null,
                BadDataFound = null
            };

            using var reader = new StreamReader(fileStream);
            using var csv = new CsvReader(reader, config);
            
            // Read records anonymously and match dynamically to support different column names
            // focusing only on Category, Item, Date, Quantity.
            var records = csv.GetRecords<dynamic>().ToList();
            if (records.Count == 0) return (false, "CSV is empty.");

            _db.DatasetRecords.RemoveRange(_db.DatasetRecords);
            await _db.SaveChangesAsync();

            var newRecords = new List<DatasetRecord>();

            foreach (var r in records)
            {
                var row = r as IDictionary<string, object>;
                if (row == null) continue;

                string GetVal(string possibleKey)
                {
                    var key = row.Keys.FirstOrDefault(k => k.Contains(possibleKey, StringComparison.OrdinalIgnoreCase));
                    return key != null ? row[key]?.ToString() ?? "" : "";
                }

                string categoryStr = GetVal("Category") ?? GetVal("ITEMDESC");
                string itemStr = GetVal("Item") ?? GetVal("ITEMNO");
                string dateStr = GetVal("Date") ?? GetVal("orderDate") ?? GetVal("Month");
                string qtyStr = GetVal("Quantity") ?? GetVal("Qty");

                if (string.IsNullOrWhiteSpace(categoryStr) || string.IsNullOrWhiteSpace(itemStr) ||
                    string.IsNullOrWhiteSpace(dateStr) || string.IsNullOrWhiteSpace(qtyStr))
                {
                    continue; // skip incomplete rows
                }

                if (DateTime.TryParse(dateStr, out DateTime dt) && double.TryParse(qtyStr, out double qty))
                {
                    newRecords.Add(new DatasetRecord
                    {
                        orderDate = dt,
                        ITEMDESC = categoryStr,
                        ITEMNO = itemStr,
                        quantity = qty
                    });
                }
            }

            _db.DatasetRecords.AddRange(newRecords);
            await _db.SaveChangesAsync(); // Commit all inserts

            return (true, $"Successfully loaded {newRecords.Count} records from CSV.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error importing dataset");
            return (false, ex.Message);
        }
    }
}
