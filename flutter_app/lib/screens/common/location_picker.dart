import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../app.dart';
import '../../theme/app_theme.dart';

/// Result handed back to the caller after the user pins a spot on the map.
class MapPickResult {
  const MapPickResult({
    required this.latitude,
    required this.longitude,
    this.address,
  });

  final double latitude;
  final double longitude;

  /// Reverse-geocoded address — only present when the user explicitly ran
  /// "Detect address", so callers never silently overwrite a typed address.
  final String? address;
}

/// Opens a full-screen OpenStreetMap picker. The pin stays glued to the
/// centre of the viewport — the user pans/zooms the map under it (the same
/// pattern as ride-hailing apps), so a single finger always places the pin
/// exactly where they want, with no drag-and-drop precision problems.
Future<MapPickResult?> showLocationPicker(
  BuildContext context, {
  double? initialLat,
  double? initialLng,
}) {
  return Navigator.of(context, rootNavigator: true).push<MapPickResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          LocationPickerScreen(initialLat: initialLat, initialLng: initialLng),
    ),
  );
}

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key, this.initialLat, this.initialLng});

  final double? initialLat;
  final double? initialLng;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  static const _addisAbaba = LatLng(9.005401, 38.763611);

  late LatLng _center;
  double _zoom = 16;
  final _map = MapController();

  bool _mapReady = false;
  bool _locating = false;
  bool _detecting = false;
  String? _address;
  String? _detectError;

  @override
  void initState() {
    super.initState();
    final has = widget.initialLat != null && widget.initialLng != null;
    _center = has
        ? LatLng(widget.initialLat!, widget.initialLng!)
        : _addisAbaba;
    _zoom = has ? 16 : 11.5;
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- actions
  Future<void> _goMyLocation() async {
    if (_locating) return;
    final messenger = ScaffoldMessenger.of(context);
    // Capture the localized message up front — `t(context)` must not be
    // touched after the async permission/GPS gaps below.
    final deniedMsg = t(context).locationDenied;
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission().timeout(
        const Duration(seconds: 8),
      );
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission().timeout(
          const Duration(seconds: 25),
        );
      }
      final denied =
          perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever;
      final serviceOn = denied
          ? false
          : await Geolocator.isLocationServiceEnabled().timeout(
              const Duration(seconds: 8),
            );
      if (denied || !serviceOn) {
        messenger.showSnackBar(SnackBar(content: Text(deniedMsg)));
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      ).timeout(const Duration(seconds: 25));
      if (!mounted || !_mapReady) return;
      _map.move(LatLng(pos.latitude, pos.longitude), 16.5);
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(deniedMsg)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(deniedMsg)));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _zoomBy(double delta) {
    if (!_mapReady) return;
    _map.move(_center, (_zoom + delta).clamp(3.0, 20.0));
  }

  /// Reverse-geocode the pin via Nominatim (OpenStreetMap's free service).
  /// Explicit-only: never runs automatically, so a saved custom address is
  /// never overwritten without the user asking for it.
  Future<void> _detectAddress() async {
    if (_detecting) return;
    setState(() {
      _detecting = true;
      _detectError = null;
    });
    void fail() {
      if (mounted) {
        setState(() {
          _detecting = false;
          _detectError = t(context).detectFailed;
        });
      }
    }

    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=${_center.latitude}'
        '&lon=${_center.longitude}'
        '&format=jsonv2&zoom=18&accept-language=en',
      );
      final res = await http
          .get(
            uri,
            headers: {if (!kIsWeb) 'User-Agent': 'velo-business-app/1.5'},
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        fail();
        return;
      }
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
      // 'name' is the short human name (road/POI); fall back to the full
      // display name when Nominatim has nothing concise for this point.
      final short = (body['name'] as String?)?.trim();
      final full = (body['display_name'] as String?)?.trim();
      final picked = (short != null && short.isNotEmpty) ? short : full;
      if (!mounted) return;
      setState(() {
        _detecting = false;
        _address = (picked == null || picked.isEmpty) ? null : picked;
        if (_address == null) _detectError = t(context).detectFailed;
      });
    } on TimeoutException {
      fail();
    } catch (_) {
      fail();
    }
  }

  void _save() {
    Navigator.of(context).pop(
      MapPickResult(
        latitude: _center.latitude,
        longitude: _center.longitude,
        address: _address,
      ),
    );
  }

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: Text(t(context).pickLocation)),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: _zoom,
              maxZoom: 20,
              onMapReady: () => _mapReady = true,
              onPositionChanged: (camera, hasGesture) {
                _center = camera.center;
                _zoom = camera.zoom;
                // The address describes a point the user has now moved away
                // from — drop it so it can't be saved against the new pin.
                if (hasGesture && _address != null && mounted) {
                  setState(() => _address = null);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: dark
                    ? 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                maxNativeZoom: 19,
                userAgentPackageName: 'app.velo.business',
              ),
            ],
          ),
          // Centre pin — shifted up by half its own height so the tip sits
          // exactly on the viewport crosshair.
          Center(
            child: IgnorePointer(
              child: FractionalTranslation(
                translation: const Offset(0, -0.5),
                child: const _PinnedMarker(),
              ),
            ),
          ),
          // Right-hand control cluster: GPS + zoom in/out.
          Positioned(
            top: 14,
            right: 14,
            child: Column(
              children: [
                _MapFab(
                  icon: _locating
                      ? Icons.location_searching_rounded
                      : Icons.my_location_rounded,
                  busy: _locating,
                  onTap: _goMyLocation,
                ),
                const SizedBox(height: 10),
                _MapFab(icon: Icons.add_rounded, onTap: () => _zoomBy(1)),
                const SizedBox(height: 10),
                _MapFab(icon: Icons.remove_rounded, onTap: () => _zoomBy(-1)),
              ],
            ),
          ),
          // Bottom info card + save.
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(AppTheme.rMd),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 18,
                          color: Colors.black.withValues(alpha: .16),
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.open_with_rounded,
                              size: 15,
                              color: theme.colorScheme.outline,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                t(context).mapHint,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_center.latitude.toStringAsFixed(5)}, '
                          '${_center.longitude.toStringAsFixed(5)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Map data © OpenStreetMap contributors',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        if (_address != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(
                                Icons.check_circle_rounded,
                                size: 16,
                                color: AppTheme.success,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _address!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (_detectError != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _detectError!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _detecting ? null : _detectAddress,
                          icon: _detecting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.travel_explore_rounded,
                                  size: 18,
                                ),
                          label: Text(t(context).detectAddress),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check_rounded, size: 20),
                    label: Text(t(context).saveLocation),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The map-centre pin with a soft ground shadow.
class _PinnedMarker extends StatelessWidget {
  const _PinnedMarker();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.location_on_rounded,
          size: 40,
          color: Theme.of(context).colorScheme.primary,
          shadows: const [
            Shadow(blurRadius: 10, color: Colors.black38, offset: Offset(0, 3)),
          ],
        ),
        Container(
          width: 7,
          height: 3,
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ],
    );
  }
}

/// Small circular floating map control (44dp touch target).
class _MapFab extends StatelessWidget {
  const _MapFab({required this.icon, required this.onTap, this.busy = false});

  final IconData icon;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 2,
      shadowColor: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: busy ? null : onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 21, color: theme.colorScheme.onSurface),
        ),
      ),
    );
  }
}
