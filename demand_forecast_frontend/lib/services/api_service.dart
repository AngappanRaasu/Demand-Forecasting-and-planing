import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:universal_html/html.dart' as html;

class ApiService {
  static const String baseUrl = 'http://192.168.1.13:5000/api';

  // ─── Database / Settings ─────────────────────────────────────────

  Future<Map<String, dynamic>> testConnection(
      String server, String port, String username, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/database/test-connection'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'server': server, 'port': port, 'username': username, 'password': password}),
    );
    return jsonDecode(res.body);
  }

  Future<Map<String, dynamic>> listDatabases(
      String server, String port, String username, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/database/list-databases'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'server': server, 'port': port, 'username': username, 'password': password}),
    );
    return jsonDecode(res.body);
  }

  Future<Map<String, dynamic>> loadDataset({
    required String sourceServer,
    required String sourcePort,
    required String sourceUsername,
    required String sourcePassword,
    required String database,
    required bool sameAsSource,
    String targetServer = '',
    String targetPort = '1433',
    String targetUsername = '',
    String targetPassword = '',
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/database/load-dataset'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sourceServer': sourceServer,
        'sourcePort': sourcePort,
        'sourceUsername': sourceUsername,
        'sourcePassword': sourcePassword,
        'database': database,
        'sameAsSource': sameAsSource,
        'targetServer': targetServer,
        'targetPort': targetPort,
        'targetUsername': targetUsername,
        'targetPassword': targetPassword,
      }),
    );
    return jsonDecode(res.body);
  }

  Future<Map<String, dynamic>> uploadExcel(List<int> bytes, String filename) async {
    var uri = Uri.parse('$baseUrl/excel/upload');
    var request = http.MultipartRequest('POST', uri);
    
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
    ));

    var response = await request.send();
    var responseBody = await response.stream.bytesToString();
    return jsonDecode(responseBody);
  }

  // ─── Forecast ────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getFilters() async {
    final res = await http.get(Uri.parse('$baseUrl/forecast/filters'));
    return jsonDecode(res.body);
  }

  Future<Map<String, dynamic>> loadForecastData({
    required String industry,
    required String company,
    required String lookback,
    required String model,
    required String period,
    int page = 1,
    int pageSize = 50,
    String searchQuery = '',
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/forecast/load-forecast-data'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'industry': industry,
        'company': company,
        'lookback': lookback,
        'model': model,
        'period': period,
        'page': page,
        'pageSize': pageSize,
        'searchQuery': searchQuery,
      }),
    );
    return jsonDecode(res.body);
  }

  Future<Map<String, dynamic>> loadCategoryItems({
    required String categoryId,
    int skip = 0,
    int pageSize = 50,
    String searchQuery = '',
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/forecast/load-category-items'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'categoryId': categoryId,
        'skip': skip,
        'pageSize': pageSize,
        'searchQuery': searchQuery,
      }),
    );
    return jsonDecode(res.body);
  }

  /// Creates a new forecast JOB and returns immediately (async fire-and-forget on backend).
  /// Returns { success, jobId, message }
  Future<Map<String, dynamic>> runForecast({
    required List<String> itemIds,
    required String model,
    required String lookback,
    required String period,
    required String jobName,
    List<String> categoryIds = const [],
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/forecast/run-forecast'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'itemIds': itemIds,
        'categoryIds': categoryIds,
        'model': model,
        'lookback': lookback,
        'period': period,
        'jobName': jobName,
      }),
    );
    return jsonDecode(res.body);
  }

  /// Fetches the forecast results for a completed job (for Preview).
  Future<Map<String, dynamic>> getJobPreview(String jobId) async {
    final res = await http.get(Uri.parse('$baseUrl/forecast/preview/$jobId'));
    return jsonDecode(res.body);
  }

  /// Downloads the Excel file for a completed job.
  Future<http.Response> downloadJobExcel(String jobId) async {
    return http.get(Uri.parse('$baseUrl/forecast/export-excel/$jobId'));
  }

  /// Gets the job list for the dashboard.
  Future<Map<String, dynamic>> getJobs() async {
    final res = await http.get(Uri.parse('$baseUrl/forecast/jobs'));
    return jsonDecode(res.body);
  }

  // ─── Utility ─────────────────────────────────────────────────────

  /// Saves bytes to user's Downloads folder.
  static Future<String?> saveExcelToDownloads(List<int> bytes, String filename) async {
    try {
      if (kIsWeb) {
        final blob = html.Blob(
          [bytes],
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', filename)
          ..click();
        html.Url.revokeObjectUrl(url);
        return filename;
      } else {
        String userProfile = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Default';
        final downloadsPath = '$userProfile\\Downloads';
        final dir = Directory(downloadsPath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        final dest = '$downloadsPath\\$filename';
        await File(dest).writeAsBytes(bytes);
        return dest;
      }
    } catch (e) {
      print('Export save error: $e');
      return null;
    }
  }
}
