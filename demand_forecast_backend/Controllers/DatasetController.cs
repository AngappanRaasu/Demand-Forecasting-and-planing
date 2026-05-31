using Microsoft.AspNetCore.Mvc;
using DemandForecastBackend.Services;

namespace DemandForecastBackend.Controllers;

[ApiController]
[Route("api/dataset")]
public class DatasetController : ControllerBase
{
    private readonly CsvImportService _csvImportService;

    public DatasetController(CsvImportService csvImportService)
    {
        _csvImportService = csvImportService;
    }

    /// <summary>POST /api/dataset/upload — import from CSV file</summary>
    [HttpPost("upload")]
    public async Task<IActionResult> UploadDataset(IFormFile file)
    {
        if (file == null || file.Length == 0)
            return BadRequest(new { success = false, message = "No file uploaded." });

        using var stream = file.OpenReadStream();
        var (success, message) = await _csvImportService.ImportFromStreamAsync(stream);

        return Ok(new { success, message });
    }

}
