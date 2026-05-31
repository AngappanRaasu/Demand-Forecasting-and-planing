using DemandForecastBackend.DTOs;
using NPOI.SS.UserModel;
using NPOI.XSSF.UserModel;

namespace DemandForecastBackend.Services;

public class ExcelExportService
{
    public byte[] GenerateForecastExcel(ForecastJobDto job)
    {
        var rawResults = job.Results.ToList();
        
        var uniqueMonthsSet = new HashSet<string>();
        var itemsList = new List<(ForecastResultDto Result, Dictionary<string, double> MonthValues, int SortIndex)>();
        int sortIndex = 0;
        
        foreach (var r in rawResults)
        {
            var monthValues = new Dictionary<string, double>();
            try
            {
                var breakdown = System.Text.Json.JsonSerializer.Deserialize<List<Dictionary<string, object>>>(r.MonthlyBreakdown ?? "[]");
                if (breakdown != null)
                {
                    foreach (var b in breakdown)
                    {
                        var m = b.ContainsKey("month") ? b["month"]?.ToString() ?? "" : "";
                        var qDb = b.ContainsKey("quantity") ? Convert.ToDouble(b["quantity"]?.ToString() ?? "0") : 0;
                        if (!string.IsNullOrEmpty(m))
                        {
                            uniqueMonthsSet.Add(m);
                            monthValues[m] = qDb;
                        }
                    }
                }
            }
            catch
            {
                // Ignore parse errors
            }

            itemsList.Add((r, monthValues, sortIndex++));
        }

        var uniqueMonths = uniqueMonthsSet.ToList();

        var results = itemsList
            .OrderBy(x => x.Result.CategoryId)
            .ThenBy(x => x.Result.ItemId)
            .ThenBy(x => x.SortIndex)
            .ToList();

        // Create new Excel workbook and sheet
        IWorkbook workbook = new XSSFWorkbook();
        ISheet sheet = workbook.CreateSheet("Forecast Results");

        // Helper to create styles
        var headers = new List<string> { "#", "Category", "Item ID" };
        headers.AddRange(uniqueMonths);
        headers.Add("Accuracy %");

        // 1. Create Header Style
        ICellStyle headerStyle = workbook.CreateCellStyle();
        headerStyle.FillForegroundColor = IndexedColors.RoyalBlue.Index;
        headerStyle.FillPattern = FillPattern.SolidForeground;
        headerStyle.Alignment = HorizontalAlignment.Center;
        headerStyle.BorderBottom = BorderStyle.Medium;
        
        IFont headerFont = workbook.CreateFont();
        headerFont.IsBold = true;
        headerFont.Color = IndexedColors.White.Index;
        headerStyle.SetFont(headerFont);

        // 2. Create Alternate Row Style
        ICellStyle altRowStyle = workbook.CreateCellStyle();
        altRowStyle.FillForegroundColor = IndexedColors.LightCornflowerBlue.Index;
        altRowStyle.FillPattern = FillPattern.SolidForeground;

        // Write Headers
        IRow headerRow = sheet.CreateRow(0);
        for (int i = 0; i < headers.Count; i++)
        {
            ICell cell = headerRow.CreateCell(i);
            cell.SetCellValue(headers[i]);
            cell.CellStyle = headerStyle;
        }

        // Write Data Rows
        string previousCategory = null;
        string previousItem = null;
        
        for (int rowIdx = 0; rowIdx < results.Count; rowIdx++)
        {
            var item = results[rowIdx];
            var r = item.Result;
            IRow row = sheet.CreateRow(rowIdx + 1);

            // Determine if we should show the string keys based on grouping matching
            string displayCategory = r.CategoryId ?? "";
            string displayItem = r.ItemId ?? "";

            if (previousCategory != null && (r.CategoryId ?? "") == previousCategory)
            {
                displayCategory = "";
                if (previousItem != null && (r.ItemId ?? "") == previousItem)
                {
                    displayItem = "";
                }
            }
            
            previousCategory = r.CategoryId ?? "";
            previousItem = r.ItemId ?? "";

            row.CreateCell(0).SetCellValue((rowIdx + 1).ToString());
            row.CreateCell(1).SetCellValue(displayCategory);
            row.CreateCell(2).SetCellValue(displayItem);

            int colIndex = 3;
            foreach (var m in uniqueMonths)
            {
                double qty = item.MonthValues.TryGetValue(m, out double val) ? val : 0;
                row.CreateCell(colIndex++).SetCellValue((int)Math.Round(qty, MidpointRounding.AwayFromZero));
            }
            
            row.CreateCell(colIndex).SetCellValue(Math.Round(r.AccuracyPercent, 2));

            // Alternate row shading (odd rows, zero-indexed)
            if (rowIdx % 2 == 1)
            {
                for (int col = 0; col < headers.Count; col++)
                {
                    var cell = row.GetCell(col) ?? row.CreateCell(col);
                    cell.CellStyle = altRowStyle;
                }
            }
        }

        // Auto-fit all columns (must be done after data is populated)
        for (int col = 0; col < headers.Count; col++)
        {
            sheet.AutoSizeColumn(col);
        }

        // Write workbook to a MemoryStream and return as byte array
        using (var memoryStream = new MemoryStream())
        {
            workbook.Write(memoryStream);
            return memoryStream.ToArray();
        }
    }
}
