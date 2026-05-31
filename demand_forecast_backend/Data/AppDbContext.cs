using Microsoft.EntityFrameworkCore;
using DemandForecastBackend.Models;

namespace DemandForecastBackend.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<DatasetRecord> DatasetRecords => Set<DatasetRecord>();
    public DbSet<ForecastJob> ForecastJobs => Set<ForecastJob>();
    public DbSet<ForecastResult> ForecastResults => Set<ForecastResult>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<DatasetRecord>()
            .ToTable("DatasetRecords");

        modelBuilder.Entity<ForecastJob>().HasMany(j => j.Results).WithOne(r => r.ForecastJob).HasForeignKey(r => r.ForecastJobId);
    }
}
