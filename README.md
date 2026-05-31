# Demand Forecasting and Planning System

## Project Overview

Demand Forecasting and Planning System is a full-stack enterprise application designed to help organizations
predict future product demand using historical business data and machine learning techniques.
The system enables users to import datasets, connect databases, generate forecasts, visualize results,
and support planning activities through an intuitive dashboard. 
By transforming raw business data into actionable insights, the platform helps improve inventory management,
resource allocation, and operational decision-making.

## Technologies Used

### Frontend

* Flutter
* Dart

### Backend

* ASP.NET Core Web API
* C#

### Database

* SQL Server
* Entity Framework Core

### Machine Learning & Analytics

* Python
* ARIMA Forecasting Model
* Data Processing Libraries

### Development Tools

* Visual Studio
* VS Code
* Git
* GitHub

## Features

* Database Connectivity and Configuration
* Excel and CSV Data Import
* Dataset Preview and Validation
* Demand Forecast Generation
* Machine Learning-Based Prediction
* Interactive Dashboard Visualization
* Forecast Reporting and Analysis
* REST API Integration
* Data Export Functionality
* Scalable Full-Stack Architecture

## Architecture

The application follows a multi-layer architecture:

### Frontend Layer

Flutter-based user interface responsible for user interaction, dashboard visualization, and API communication.

### Backend Layer

ASP.NET Core Web API handles business logic, data processing, forecasting requests, and database operations.

### Database Layer

SQL Server stores historical sales data, forecast results, and application-related information.

### Machine Learning Layer

Python forecasting scripts process historical data and generate demand predictions that are returned to the backend through API integration.

## How to Run

### Backend Setup

```bash
cd demand_forecast_backend
dotnet restore
dotnet run
```

The API will start on the configured localhost port.

### Frontend Setup

```bash
cd demand_forecast_frontend
flutter pub get
flutter run
```

### Database Setup

1. Create a SQL Server database.
2. Execute the `SampleSourceDB.sql` script.
3. Update the connection string in `appsettings.json`.
4. Run the backend application.

### Forecasting Workflow

1. Configure Database Connection.
2. Import Dataset.
3. Preview and Validate Data.
4. Generate Forecast.
5. Visualize Results.
6. Export Forecast Reports.

## Project Outcome

This project demonstrates full-stack development, 
REST API design, database integration, machine learning integration,
and enterprise software architecture.
It provides an end-to-end forecasting solution that helps organizations make accurate, data-driven planning decisions.

## Author

**Angappan Raasu**
Software Engineer | Full-Stack Developer | Demand Forecasting Enthusiast
