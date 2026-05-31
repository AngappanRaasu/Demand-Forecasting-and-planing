using Microsoft.Data.SqlClient;

namespace DemandForecastBackend.Services;

public class DatabaseService
{
    /// <summary>
    /// Builds a connection string from only the credentials the user provided.
    /// NO fallbacks. NO guessing. If credentials are wrong, the call will fail
    /// and the caller is responsible for surfacing the error to the user.
    /// </summary>
    private string BuildConnectionString(
        string server, string port, string username, string password,
        string database = "master")
    {
        var builder = new SqlConnectionStringBuilder
        {
            InitialCatalog       = database,
            TrustServerCertificate = true,
            ConnectTimeout       = 15
        };

        // The user explicitly wants port to be required
        if (string.IsNullOrWhiteSpace(port))
            throw new ArgumentException("Port is required.");

        // If the server already contains a comma or slash we just use it, otherwise format with port
        if (!server.Contains("\\") && !server.Contains(","))
            builder.DataSource = $"{server},{port}";
        else
            builder.DataSource = server; // It's a named instance, port might be ignored by SQL client but we still require user to input it as requested

        // Always use SQL Server Authentication when username is provided
        if (!string.IsNullOrWhiteSpace(username))
        {
            builder.UserID   = username;
            builder.Password = password ?? "";
            builder.IntegratedSecurity = false;
        }
        else
        {
            // Only fall back to Windows Auth when the user explicitly left username blank
            builder.IntegratedSecurity = true;
        }

        return builder.ConnectionString;
    }

    /// <summary>
    /// Tests the connection using EXACTLY the credentials the user provided.
    /// Returns a clear error message if login fails — no silent fallback.
    /// </summary>
    public async Task<(bool success, string message)> TestConnectionAsync(
        string server, string port, string username, string password)
    {
        if (string.IsNullOrWhiteSpace(server))
            return (false, "Server name is required.");
        if (string.IsNullOrWhiteSpace(port))
            return (false, "Port is required.");
        if (string.IsNullOrWhiteSpace(username))
            return (false, "Username is required.");

        try
        {
            var connStr = BuildConnectionString(server, port, username, password);
            await using var conn = new SqlConnection(connStr);
            await conn.OpenAsync();
            return (true, $"Connected successfully to {conn.DataSource}!");
        }
        catch (Exception ex)
        {
            return (false, $"Connection failed: {ex.Message}");
        }
    }

    /// <summary>
    /// Lists databases using EXACTLY the credentials the user provided.
    /// No fallback — if credentials are wrong, returns the real error.
    /// </summary>
    public async Task<(bool success, List<string> databases, string message)> ListDatabasesAsync(
        string server, string port, string username, string password)
    {
        if (string.IsNullOrWhiteSpace(server))
            return (false, new List<string>(), "Server name is required.");
        if (string.IsNullOrWhiteSpace(port))
            return (false, new List<string>(), "Port is required.");
        if (string.IsNullOrWhiteSpace(username))
            return (false, new List<string>(), "Username is required.");

        try
        {
            var connStr = BuildConnectionString(server, port, username, password);
            await using var conn = new SqlConnection(connStr);
            await conn.OpenAsync();

            var databases = new List<string>();
            const string sql =
                "SELECT name FROM sys.databases " +
                "WHERE name NOT IN ('master','tempdb','model','msdb') " +
                "ORDER BY name";

            await using var cmd    = new SqlCommand(sql, conn);
            await using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
                databases.Add(reader.GetString(0));

            return (true, databases, $"Found {databases.Count} database(s).");
        }
        catch (Exception ex)
        {
            return (false, new List<string>(), $"Failed to list databases: {ex.Message}");
        }
    }

    /// <summary>
    /// Builds the connection string for the source database using EXACTLY
    /// the credentials the user provided. No fallback, no override.
    /// </summary>
    public string BuildSourceConnectionString(
        string server, string port, string username, string password, string database)
    {
        if (string.IsNullOrWhiteSpace(server))
            throw new Exception("Source server name is required.");
        if (string.IsNullOrWhiteSpace(port))
            throw new Exception("Source port is required.");
        if (string.IsNullOrWhiteSpace(username))
            throw new Exception("Source username is required.");

        return BuildConnectionString(server, port, username, password, database);
    }
}
