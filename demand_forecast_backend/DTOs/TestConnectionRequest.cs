namespace DemandForecastBackend.DTOs;

public class TestConnectionRequest
{
    public string Server { get; set; } = string.Empty;
    public string Port { get; set; } = "1433";
    public string Username { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
}
