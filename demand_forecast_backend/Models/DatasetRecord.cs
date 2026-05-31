namespace DemandForecastBackend.Models;

public class DatasetRecord
{
    public int Id { get; set; }
    public DateTime orderDate { get; set; }
    public string ITEMDESC { get; set; } = string.Empty;
    public string ITEMNO { get; set; } = string.Empty;
    public double quantity { get; set; }
}
