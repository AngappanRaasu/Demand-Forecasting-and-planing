namespace DemandForecastBackend.Models;

public class ForecastResult
{
    public int Id { get; set; }
    public int ForecastJobId { get; set; }
    public ForecastJob ForecastJob { get; set; } = null!;
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
