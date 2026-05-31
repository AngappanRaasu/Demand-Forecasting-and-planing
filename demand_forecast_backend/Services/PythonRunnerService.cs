using System.Diagnostics;
using System.Text.Json;

namespace DemandForecastBackend.Services;

public class PythonRunnerService
{
    private readonly ILogger<PythonRunnerService> _logger;

    public PythonRunnerService(ILogger<PythonRunnerService> logger)
    {
        _logger = logger;
    }

    /// <summary>
    /// Runs the Python forecast script.
    /// Input: JSON payload with historicalData, model, forecastPeriods.
    /// Output: JSON array of { itemId, itemName, categoryId, categoryName, forecastYear, forecastedQuantity, accuracyPercent }
    /// </summary>
    public async Task<List<Dictionary<string, object>>> RunForecastAsync(object payload)
    {
        var scriptPath = Path.Combine(Directory.GetCurrentDirectory(), "Scripts", "run_forecast.py");
        if (!File.Exists(scriptPath))
        {
            _logger.LogWarning("Python script not found at {path}. Returning mock results.", scriptPath);
            return GenerateMockResults(payload);
        }

        var jsonInput = JsonSerializer.Serialize(payload);

        var psi = new ProcessStartInfo
        {
            FileName = "python",
            Arguments = $"\"{scriptPath}\"",
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        try
        {
            using var process = Process.Start(psi)!;
            await process.StandardInput.WriteLineAsync(jsonInput);
            process.StandardInput.Close();

            var stdout = await process.StandardOutput.ReadToEndAsync();
            var stderr = await process.StandardError.ReadToEndAsync();
            await process.WaitForExitAsync();

            // Log stderr at debug level (it contains Prophet/cmdstanpy info messages)
            if (!string.IsNullOrWhiteSpace(stderr))
                _logger.LogDebug("Python stderr: {stderr}", stderr);

            if (process.ExitCode != 0)
            {
                // Try to extract the real Python exception from stdout JSON
                string realError = stderr;
                try
                {
                    var errList = JsonSerializer.Deserialize<List<Dictionary<string, object>>>(stdout);
                    if (errList != null && errList.Count > 0 && errList[0].ContainsKey("error"))
                        realError = errList[0]["error"]?.ToString() ?? stderr;
                }
                catch { /* fallback to stderr */ }

                _logger.LogError("Python script exited {code}. Error: {err}", process.ExitCode, realError);
                throw new Exception($"Python error: {realError}");
            }

            var results = JsonSerializer.Deserialize<List<Dictionary<string, object>>>(stdout.Trim());
            return results ?? new List<Dictionary<string, object>>();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to run Python forecast script");
            throw;
        }
    }

    private List<Dictionary<string, object>> GenerateMockResults(object payload)
    {
        // Returns mock forecast data when Python script is not yet available
        return new List<Dictionary<string, object>>
        {
            new() { ["itemId"] = "1", ["itemName"] = "Item A", ["categoryId"] = "1",
                    ["categoryName"] = "Category A", ["forecastYear"] = "2025",
                    ["forecastedQuantity"] = 1200.0, ["accuracyPercent"] = 87.5 },
            new() { ["itemId"] = "2", ["itemName"] = "Item B", ["categoryId"] = "1",
                    ["categoryName"] = "Category A", ["forecastYear"] = "2025",
                    ["forecastedQuantity"] = 850.0, ["accuracyPercent"] = 91.2 },
        };
    }
}
