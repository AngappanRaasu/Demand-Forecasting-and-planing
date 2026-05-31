namespace DemandForecastBackend.DTOs;

public class LoadForecastDataRequest
{
    public string Industry { get; set; } = string.Empty;
    public string Company { get; set; } = string.Empty;
    public string Lookback { get; set; } = string.Empty;
    public string Model { get; set; } = string.Empty;
    public string Period { get; set; } = string.Empty;
    
    // Pagination and Search
    public int Page { get; set; } = 1;
    public int PageSize { get; set; } = 50;
    public string SearchQuery { get; set; } = string.Empty;
}
