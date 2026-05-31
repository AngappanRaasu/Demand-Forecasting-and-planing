namespace DemandForecastBackend.DTOs;

public class LoadCategoryItemsRequest
{
    public string CategoryId { get; set; } = string.Empty;
    /// <summary>Number of items to skip (offset-based, replaces page-number approach).</summary>
    public int Skip { get; set; } = 0;
    public int PageSize { get; set; } = 50;
    public string SearchQuery { get; set; } = string.Empty;
}
