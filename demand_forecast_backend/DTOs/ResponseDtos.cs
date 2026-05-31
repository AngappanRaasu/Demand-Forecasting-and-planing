namespace DemandForecastBackend.DTOs;

public class CategoryDto
{
    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public List<ItemDto> Items { get; set; } = new();
}

public class ItemDto
{
    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string CategoryId { get; set; } = string.Empty;
}

public class ForecastResultDto
{
    public string CategoryId { get; set; } = string.Empty;
    public string CategoryName { get; set; } = string.Empty;
    public string ItemId { get; set; } = string.Empty;
    public string ItemName { get; set; } = string.Empty;
    public string ForecastYear { get; set; } = string.Empty;
    public string Model { get; set; } = string.Empty;
    public double AccuracyPercent { get; set; }
    public double ForecastedQuantity { get; set; }
    public string MonthlyBreakdown { get; set; } = "[]";
}

public class ForecastJobDto
{
    public int Id { get; set; }
    public string JobId { get; set; } = string.Empty;
    public string JobName { get; set; } = string.Empty;
    public string Model { get; set; } = string.Empty;
    public string Lookback { get; set; } = string.Empty;
    public string Period { get; set; } = string.Empty;
    public string SelectedCategories { get; set; } = string.Empty;
    public string SelectedItems { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public List<ForecastResultDto> Results { get; set; } = new();
}
