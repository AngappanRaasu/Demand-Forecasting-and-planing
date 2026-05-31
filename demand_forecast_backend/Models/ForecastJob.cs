namespace DemandForecastBackend.Models;

public class ForecastJob
{
    public int Id { get; set; }
    public string JobId { get; set; } = string.Empty;   // e.g. "JOB-101"
    public string JobName { get; set; } = string.Empty;
    public string Industry { get; set; } = string.Empty;
    public string Company { get; set; } = string.Empty;
    public string Model { get; set; } = string.Empty;
    public string Lookback { get; set; } = string.Empty;
    public string Period { get; set; } = string.Empty;
    public string SelectedCategories { get; set; } = string.Empty; // JSON array
    public string SelectedItems { get; set; } = string.Empty;      // JSON array
    public string Status { get; set; } = "Pending";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public ICollection<ForecastResult> Results { get; set; } = new List<ForecastResult>();
}
