using Microsoft.AspNetCore.Mvc;
using DemandForecastBackend.Services;

namespace DemandForecastBackend.Controllers;

[ApiController]
[Route("api/excel")]
public class ExcelUploadController : ControllerBase
{
    private readonly ExcelImportService _excelImportService;

    public ExcelUploadController(ExcelImportService excelImportService)
    {
        _excelImportService = excelImportService;
    }

    /// <summary>POST /api/excel/upload — import from an Excel (.xlsx) file</summary>
    [HttpPost("upload")]
    [DisableRequestSizeLimit] // Allow large files
    public async Task<IActionResult> UploadExcel(IFormFile file)
    {
        try
        {
            if (file == null || file.Length == 0)
                return BadRequest(new { success = false, message = "No file uploaded." });

            var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
            if (ext != ".xlsx" && ext != ".xls" && ext != ".csv")
                return BadRequest(new { success = false, message = "Only .xlsx, .xls, and .csv files are supported." });

            using var stream = file.OpenReadStream();
            var (success, rowsInserted, message) = await _excelImportService.ImportFromStreamAsync(stream, file.FileName);

            return Ok(new { success, rowsInserted, message });
        }
        catch (Exception ex)
        {
            return Ok(new { success = false, message = $"Error uploading Excel: {ex.Message}" }); // Return 200 with success = false so frontend parses message nicely
        }
    }
}
