using Microsoft.AspNetCore.Mvc;
using DemandForecastBackend.DTOs;
using DemandForecastBackend.Services;

namespace DemandForecastBackend.Controllers;

[ApiController]
[Route("api/forecast")]
public class ForecastController : ControllerBase
{
    private readonly ForecastService _forecastService;
    private readonly ExcelExportService _excelService;

    public ForecastController(ForecastService forecastService, ExcelExportService excelService)
    {
        _forecastService = forecastService;
        _excelService = excelService;
    }

    /// <summary>GET /api/forecast/filters</summary>
    [HttpGet("filters")]
    public async Task<IActionResult> GetFilters()
    {
        var filters = await _forecastService.GetFiltersAsync();
        return Ok(filters);
    }

    /// <summary>POST /api/forecast/load-forecast-data</summary>
    [HttpPost("load-forecast-data")]
    public async Task<IActionResult> LoadForecastData([FromBody] LoadForecastDataRequest req)
    {
        var (success, categories, totalCount, message) = await _forecastService.LoadForecastDataAsync(req);
        return Ok(new { success, categories, totalCount, message });
    }

    /// <summary>POST /api/forecast/load-category-items</summary>
    [HttpPost("load-category-items")]
    public async Task<IActionResult> LoadCategoryItems([FromBody] LoadCategoryItemsRequest req)
    {
        var (success, items, totalCount, message) = await _forecastService.LoadCategoryItemsAsync(req);
        return Ok(new { success, items, totalCount, message });
    }

    /// <summary>
    /// POST /api/forecast/run-forecast
    /// Creates a new forecast JOB (Pending) and starts it in the background.
    /// Returns immediately with the new JobId — user does NOT wait.
    /// </summary>
    [HttpPost("run-forecast")]
    public async Task<IActionResult> RunForecast([FromBody] PreviewRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.JobName))
            return BadRequest(new { success = false, message = "Job Name is required." });

        var (success, jobId, message) = await _forecastService.StartForecastJobAsync(req);

        if (!success)
            return Ok(new { success = false, jobId = (string?)null, message });

        return Ok(new { success = true, jobId, message });
    }

    /// <summary>
    /// GET /api/forecast/preview/{jobId}
    /// Returns the forecast results stored for a specific completed job.
    /// </summary>
    [HttpGet("preview/{jobId}")]
    public async Task<IActionResult> PreviewJob(string jobId)
    {
        var (success, job, message) = await _forecastService.GetJobResultsAsync(jobId);
        if (!success)
            return Ok(new { success = false, message });

        return Ok(new { success = true, job });
    }

    /// <summary>
    /// GET /api/forecast/jobs — dashboard data (job list without results)
    /// </summary>
    [HttpGet("jobs")]
    public async Task<IActionResult> GetJobs()
    {
        try
        {
            var jobs = await _forecastService.GetJobsAsync();
            return Ok(new { success = true, jobs });
        }
        catch (Exception ex)
        {
            var inner = ex.InnerException?.Message ?? ex.Message;
            return Ok(new { success = false, jobs = Array.Empty<object>(), message = inner });
        }
    }

    /// <summary>
    /// GET /api/forecast/export-excel/{jobId}
    /// Generates and downloads Excel for a completed job by its JobId.
    /// </summary>
    [HttpGet("export-excel/{jobId}")]
    public async Task<IActionResult> ExportExcel(string jobId)
    {
        var (success, job, message) = await _forecastService.GetJobResultsAsync(jobId);
        if (!success || job == null)
            return BadRequest(new { success = false, message });

        var bytes = _excelService.GenerateForecastExcel(job);
        return File(
            bytes,
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            $"Forecast_{job.JobId}_{DateTime.Now:yyyyMMdd_HHmmss}.xlsx");
    }
}
