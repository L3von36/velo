import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Typed exception surfaced to UI layer.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.fieldErrors});
  final String message;
  final int? statusCode;
  final Map<String, dynamic>? fieldErrors;

  @override
  String toString() => message;
}

/// Dio-based API client with JWT auth + token refresh.
///
/// Base URL strategy:
///  - Web: same-origin `/api` (proxied by the host server in the sandbox).
///  - Native: configurable server URL persisted in SharedPreferences.
class ApiClient {
  ApiClient._() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Content-Type': 'application/json'},
    ));
    _dio.interceptors.add(_authInterceptor());
  }
  static final ApiClient I = ApiClient._();
  late final Dio _dio;
  String? _accessToken;
  String? _refreshToken;

  static const _kServer = 'server_url';
  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';

  String _baseUrl(String server) {
    if (kIsWeb) return '$server/api';
    return server.endsWith('/api') ? server : '$server/api';
  }

  Future<String> get serverUrl async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_kServer) ??
        (kIsWeb ? '' : 'http://10.0.2.2:8000'); // Android emulator → host
  }

  Future<void> setServerUrl(String url) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kServer, url.endsWith('/api') ? url.substring(0, url.length - 4) : url);
  }

  Future<void> loadTokens() async {
    final sp = await SharedPreferences.getInstance();
    _accessToken = sp.getString(_kAccess);
    _refreshToken = sp.getString(_kRefresh);
  }

  Future<void> saveTokens(String access, String refresh) async {
    _accessToken = access;
    _refreshToken = refresh;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kAccess, access);
    await sp.setString(_kRefresh, refresh);
  }

  bool get hasTokens => _accessToken != null;

  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kAccess);
    await sp.remove(_kRefresh);
  }

  Interceptor _authInterceptor() => InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_accessToken != null) {
            options.headers['Authorization'] = 'Bearer $_accessToken';
          }
          return handler.next(options);
        },
        onError: (e, handler) async {
          // Try a single refresh on 401.
          if (e.response?.statusCode == 401 && _refreshToken != null) {
            final ok = await _tryRefresh();
            if (ok) {
              try {
                final opts = e.requestOptions;
                opts.headers['Authorization'] = 'Bearer $_accessToken';
                final resp = await _dio.fetch(opts);
                return handler.resolve(resp);
              } catch (_) {/* fall through */}
            }
          }
          handler.next(e);
        },
      );

  Future<bool> _tryRefresh() async {
    try {
      final server = await serverUrl;
      final resp = await Dio(BaseOptions())
          .post('${_baseUrl(server)}/auth/refresh',
              data: {'refresh': _refreshToken});
      await saveTokens(resp.data['access'], resp.data['refresh'] ?? _refreshToken!);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> get(String path,
      {Map<String, dynamic>? query}) async {
    try {
      final server = await serverUrl;
      final r = await _dio.get('${_baseUrl(server)}$path', queryParameters: query);
      return _asMap(r.data);
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  Future<Map<String, dynamic>> post(String path, {Object? data}) async {
    try {
      final server = await serverUrl;
      final r = await _dio.post('${_baseUrl(server)}$path', data: data);
      return _asMap(r.data);
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  Future<Map<String, dynamic>> patch(String path, {Object? data}) async {
    try {
      final server = await serverUrl;
      final r = await _dio.patch('${_baseUrl(server)}$path', data: data);
      return _asMap(r.data);
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  Future<Map<String, dynamic>> delete(String path) async {
    try {
      final server = await serverUrl;
      final r = await _dio.delete('${_baseUrl(server)}$path');
      return _asMap(r.data);
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  Map<String, dynamic> _asMap(dynamic d) =>
      d is Map<String, dynamic> ? d : <String, dynamic>{};

  ApiException _toApiException(DioException e) {
    final resp = e.response;
    if (resp == null) {
      return ApiException('Cannot reach the server. Check your connection.');
    }
    final data = resp.data;
    Map<String, dynamic>? fields;
    String message = 'Request failed (${resp.statusCode})';
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      if (m['detail'] is String) {
        message = m['detail'] as String;
      } else if (m.isNotEmpty) {
        fields = m.map((k, v) => MapEntry(k, v.toString()));
        final first = m.entries.first;
        message = '${first.key}: ${first.value}'.replaceAll(RegExp(r'[\[\]{}]'), '');
      }
    }
    return ApiException(message, statusCode: resp.statusCode, fieldErrors: fields);
  }
}
