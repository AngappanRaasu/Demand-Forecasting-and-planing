namespace DemandForecastBackend.DTOs;

public class PreviewRequest
{
    public List<string> ItemIds { get; set; } = new();
    public List<string> CategoryIds { get; set; } = new();
    public string Model { get; set; } = string.Empty;
    public string Lookback { get; set; } = string.Empty;
    public string Period { get; set; } = string.Empty;
    public string JobName { get; set; } = "Forecast Job";
}
