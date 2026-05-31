using Microsoft.AspNetCore.Mvc;
using DemandForecastBackend.DTOs;
using DemandForecastBackend.Services;

namespace DemandForecastBackend.Controllers;

[ApiController]
[Route("api/database")]
public class DatabaseController : ControllerBase
{
    private readonly DatabaseService _dbService;
    private readonly ForecastService _forecastService;

    public DatabaseController(DatabaseService dbService, ForecastService forecastService)
    {
        _dbService = dbService;
        _forecastService = forecastService;
    }

    /// <summary>POST /api/database/test-connection</summary>
    [HttpPost("test-connection")]
    public async Task<IActionResult> TestConnection([FromBody] TestConnectionRequest req)
    {
        var (success, message) = await _dbService.TestConnectionAsync(req.Server, req.Port, req.Username, req.Password);
        return Ok(new { success, message });
    }

    /// <summary>POST /api/database/list-databases</summary>
    [HttpPost("list-databases")]
    public async Task<IActionResult> ListDatabases([FromBody] TestConnectionRequest req)
    {
        var (success, databases, message) = await _dbService.ListDatabasesAsync(req.Server, req.Port, req.Username, req.Password);
        return Ok(new { success, databases, message });
    }

    /// <summary>POST /api/database/load-dataset</summary>
    [HttpPost("load-dataset")]
    public async Task<IActionResult> LoadDataset([FromBody] LoadDatasetRequest req)
    {
        try
        {
            string sourceConnStr = _dbService.BuildSourceConnectionString(
                req.SourceServer, req.SourcePort, req.SourceUsername, req.SourcePassword, req.Database);

            // Fetch the flat table data from the remote source into our local DatasetRecords table
            await _forecastService.LoadDatasetFromSourceAsync(sourceConnStr);

            return Ok(new { success = true, message = "Dataset loaded from remote database successfully" });
        }
        catch (Exception ex)
        {
            // We want to return Ok with success = false so the frontend catches the message nicely
            return Ok(new { success = false, message = ex.Message });
        }
    }
}
