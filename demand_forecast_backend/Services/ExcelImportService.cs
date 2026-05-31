using Microsoft.EntityFrameworkCore;
using NPOI.HSSF.UserModel;
using NPOI.SS.UserModel;
using NPOI.XSSF.UserModel;
using DemandForecastBackend.Data;
using DemandForecastBackend.Models;
using System.Globalization;

namespace DemandForecastBackend.Services;

public class ExcelImportService
{
    private readonly AppDbContext _db;
    private readonly ILogger<ExcelImportService> _logger;

    public ExcelImportService(AppDbContext db, ILogger<ExcelImportService> logger)
    {
        _db = db;
        _logger = logger;
    }

    public async Task<(bool success, int rowsInserted, string message)> ImportFromStreamAsync(Stream stream, string fileName)
    {
        try
        {
            _logger.LogInformation("Starting Excel import...");

            var newRecords = new List<DatasetRecord>();
            var ext = Path.GetExtension(fileName).ToLowerInvariant();

            if (ext == ".csv")
            {
                using var reader = new StreamReader(stream);
                string? headerLine = await reader.ReadLineAsync();
                if (string.IsNullOrWhiteSpace(headerLine))
                    return (false, 0, "CSV file is empty or missing a header row.");

                var headers = headerLine.Split(',').Select(h => h.Trim('\"', ' ')).ToList();
                var colMap = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
                for (int j = 0; j < headers.Count; j++)
                {
                    colMap[headers[j]] = j;
                }

                var requiredCols = new[] { "ORDERDATE", "ITEMDESC", "ITEMNO", "QUANTITY" };
                var missingCols = requiredCols.Where(c => !colMap.ContainsKey(c)).ToList();

                if (missingCols.Any())
                {
                    return (false, 0, $"Missing required columns: {string.Join(", ", missingCols)}");
                }

                int dateIdx = colMap["ORDERDATE"];
                int descIdx = colMap["ITEMDESC"];
                int noIdx = colMap["ITEMNO"];
                int qtyIdx = colMap["QUANTITY"];

                string? line;
                while ((line = await reader.ReadLineAsync()) != null)
                {
                    if (string.IsNullOrWhiteSpace(line)) continue;

                    // Basic CSV parsing. A real robust parser might be needed for quoted commas.
                    var cols = ParseCsvLine(line);
                    if (cols.Count <= Math.Max(Math.Max(dateIdx, descIdx), Math.Max(noIdx, qtyIdx))) continue;

                    var dateStr = cols[dateIdx];
                    var descStr = cols[descIdx];
                    var noStr   = cols[noIdx];
                    var qtyStr  = cols[qtyIdx];

                    if (string.IsNullOrWhiteSpace(descStr) || string.IsNullOrWhiteSpace(noStr)) continue;

                    if (!DateTime.TryParse(dateStr, out DateTime dateVal)) continue;
                    if (!double.TryParse(qtyStr, out double qtyVal)) continue;

                    newRecords.Add(new DatasetRecord
                    {
                        orderDate = dateVal,
                        ITEMDESC  = descStr,
                        ITEMNO    = noStr,
                        quantity  = qtyVal
                    });
                }
            }
            else
            {
                stream.Position = 0;
                IWorkbook workbook;
                if (ext == ".xls")
                {
                    workbook = new HSSFWorkbook(stream);
                }
                else
                {
                    workbook = new XSSFWorkbook(stream);
                }

                ISheet sheet = workbook.GetSheetAt(0);
                if (sheet == null)
                    return (false, 0, "Excel file is empty or missing a worksheet.");

                IRow headerRow = sheet.GetRow(0);
                if (headerRow == null)
                    return (false, 0, "Excel header row is missing.");

                var colMap = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
                for (int j = 0; j < headerRow.LastCellNum; j++)
                {
                    var cell = headerRow.GetCell(j);
                    if (cell != null && !string.IsNullOrWhiteSpace(cell.ToString()))
                    {
                        colMap[cell.ToString()!.Trim()] = j;
                    }
                }

                var requiredCols = new[] { "ORDERDATE", "ITEMDESC", "ITEMNO", "QUANTITY" };
                var missingCols = requiredCols.Where(c => !colMap.ContainsKey(c)).ToList();

                if (missingCols.Any())
                {
                    return (false, 0, $"Missing required columns: {string.Join(", ", missingCols)}");
                }

                int dateIdx = colMap["ORDERDATE"];
                int descIdx = colMap["ITEMDESC"];
                int noIdx = colMap["ITEMNO"];
                int qtyIdx = colMap["QUANTITY"];

                for (int i = 1; i <= sheet.LastRowNum; i++)
                {
                    IRow row = sheet.GetRow(i);
                    if (row == null) continue;

                    var dateCell = row.GetCell(dateIdx);
                    var descCell = row.GetCell(descIdx);
                    var noCell   = row.GetCell(noIdx);
                    var qtyCell  = row.GetCell(qtyIdx);

                    if (dateCell == null || descCell == null || noCell == null || qtyCell == null)
                        continue;

                    DateTime dateVal;
                    if (dateCell.CellType == CellType.Numeric && DateUtil.IsCellDateFormatted(dateCell))
                    {
                        dateVal = dateCell.DateCellValue ?? DateTime.MinValue;
                    }
                    else
                    {
                        var dateStr = dateCell.ToString()?.Trim();
                        if (string.IsNullOrWhiteSpace(dateStr)) continue;
                        if (!DateTime.TryParse(dateStr, out dateVal)) continue;
                    }

                    var descStr = descCell.ToString()?.Trim() ?? "";
                    var noStr   = noCell.ToString()?.Trim() ?? "";

                    if (string.IsNullOrWhiteSpace(descStr) || string.IsNullOrWhiteSpace(noStr))
                        continue;

                    double qtyVal;
                    if (qtyCell.CellType == CellType.Numeric)
                    {
                        qtyVal = qtyCell.NumericCellValue;
                    }
                    else
                    {
                        var qtyStr = qtyCell.ToString()?.Trim();
                        if (string.IsNullOrWhiteSpace(qtyStr)) continue;
                        if (!double.TryParse(qtyStr, out qtyVal)) continue;
                    }

                    newRecords.Add(new DatasetRecord
                    {
                        orderDate = dateVal,
                        ITEMDESC  = descStr,
                        ITEMNO    = noStr,
                        quantity  = qtyVal
                    });
                }
            }

            if (!newRecords.Any())
            {
                return (false, 0, "File contains no valid data rows.");
            }

            _logger.LogInformation($"Parsed {newRecords.Count} valid rows. Clearing existing data...");

            // 4. Update Database
            _db.DatasetRecords.RemoveRange(_db.DatasetRecords);
            await _db.SaveChangesAsync(); // Optional: commit delete first

            _db.DatasetRecords.AddRange(newRecords);
            await _db.SaveChangesAsync();

            _logger.LogInformation($"Successfully inserted {newRecords.Count} records from Excel.");

            return (true, newRecords.Count, "Uploaded successfully");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error importing Excel dataset.");
            return (false, 0, $"Error importing Excel: {ex.Message}");
        }
    }

    private List<string> ParseCsvLine(string line)
    {
        var result = new List<string>();
        bool inQuotes = false;
        int start = 0;
        for (int i = 0; i < line.Length; i++)
        {
            if (line[i] == '\"')
            {
                inQuotes = !inQuotes;
            }
            else if (line[i] == ',' && !inQuotes)
            {
                result.Add(line.Substring(start, i - start).Trim('\"', ' '));
                start = i + 1;
            }
        }
        result.Add(line.Substring(start).Trim('\"', ' '));
        return result;
    }
}
