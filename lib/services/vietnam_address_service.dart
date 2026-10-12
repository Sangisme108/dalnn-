import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import '../utils/constants.dart';

class VietnamAddressService {
  static const _assetPath = 'assets/data/vietnam_address.json';
  static const _cacheKey = 'vietnam_address_json';
  static const _cacheUpdatedAtKey = 'vietnam_address_updated_at';
  static const _apiUrl = 'https://provinces.open-api.vn/api/?depth=3';

  static List<dynamic>? _memoryData;
  static Future<void>? _refreshFuture;

  static Future<List<dynamic>> load() async {
    final memoryData = _memoryData;
    if (memoryData != null && memoryData.isNotEmpty) return memoryData;

    final settings = Hive.box(AppConstants.settingsBox);
    final cachedJson = settings.get(_cacheKey)?.toString();
    if (cachedJson != null && cachedJson.isNotEmpty) {
      final cachedData = _decode(cachedJson);
      if (cachedData.isNotEmpty) {
        _memoryData = cachedData;
        _refreshInBackground();
        return cachedData;
      }
    }

    try {
      final bundledJson = await rootBundle.loadString(_assetPath);
      final bundledData = _decode(bundledJson);
      if (bundledData.isNotEmpty) {
        _memoryData = bundledData;
        unawaited(settings.put(_cacheKey, bundledJson));
        _refreshInBackground();
        return bundledData;
      }
    } catch (_) {
      // Network fallback below handles missing or invalid bundled data.
    }

    return refresh();
  }

  static Future<List<dynamic>> refresh() async {
    final response = await http
        .get(Uri.parse(_apiUrl))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final rawJson = utf8.decode(response.bodyBytes);
    final data = _decode(rawJson);
    if (data.isEmpty) throw Exception('Danh sách địa chỉ trống');

    _memoryData = data;
    final settings = Hive.box(AppConstants.settingsBox);
    await Future.wait([
      settings.put(_cacheKey, rawJson),
      settings.put(_cacheUpdatedAtKey, DateTime.now().toIso8601String()),
    ]);
    return data;
  }

  static List<dynamic> _decode(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      return decoded is List ? decoded : const [];
    } catch (_) {
      return const [];
    }
  }

  static void _refreshInBackground() {
    if (_refreshFuture != null) return;
    _refreshFuture = refresh()
        .then<void>((_) {})
        .catchError((_) {})
        .whenComplete(() => _refreshFuture = null);
  }
}
