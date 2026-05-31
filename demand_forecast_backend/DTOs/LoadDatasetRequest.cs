namespace DemandForecastBackend.DTOs;

public class LoadDatasetRequest
{
    public string SourceServer { get; set; } = string.Empty;
    public string SourcePort { get; set; } = "1433";
    public string SourceUsername { get; set; } = string.Empty;
    public string SourcePassword { get; set; } = string.Empty;
    public string Database { get; set; } = string.Empty;
    public bool SameAsSource { get; set; } = true;
    public string TargetServer { get; set; } = string.Empty;
    public string TargetPort { get; set; } = "1433";
    public string TargetUsername { get; set; } = string.Empty;
    public string TargetPassword { get; set; } = string.Empty;
}
