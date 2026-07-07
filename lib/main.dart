import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

void main() {
  runApp(const StadiumlyApp());
}

class StadiumlyApp extends StatelessWidget {
  const StadiumlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF147A52);

    return MaterialApp(
      title: 'Stadiumly',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        scaffoldBackgroundColor: const Color(0xFFF4F7F2),
        useMaterial3: true,
      ),
      home: const WaypointMapScreen(),
    );
  }
}

class Waypoint {
  const Waypoint({
    required this.id,
    required this.name,
    required this.position,
    required this.category,
    this.province = '',
    this.county = '',
    this.municipality = '',
    this.city = '',
    this.visited = false,
  });

  final int id;
  final String name;
  final LatLng position;
  final String category;
  final String province;
  final String county;
  final String municipality;
  final String city;
  final bool visited;

  Waypoint copyWith({
    String? name,
    LatLng? position,
    String? category,
    String? province,
    String? county,
    String? municipality,
    String? city,
    bool? visited,
  }) {
    return Waypoint(
      id: id,
      name: name ?? this.name,
      position: position ?? this.position,
      category: category ?? this.category,
      province: province ?? this.province,
      county: county ?? this.county,
      municipality: municipality ?? this.municipality,
      city: city ?? this.city,
      visited: visited ?? this.visited,
    );
  }
}

class AdminDivision {
  const AdminDivision({
    this.province = '',
    this.county = '',
    this.municipality = '',
    this.city = '',
  });

  final String province;
  final String county;
  final String municipality;
  final String city;
}

class AdminBoundary {
  const AdminBoundary({required this.polygons});

  final List<List<LatLng>> polygons;
}

double _distanceBetweenMeters(LatLng from, LatLng to) {
  const earthRadiusMeters = 6371000.0;
  final fromLat = from.latitude * math.pi / 180;
  final toLat = to.latitude * math.pi / 180;
  final latDelta = (to.latitude - from.latitude) * math.pi / 180;
  final lonDelta = (to.longitude - from.longitude) * math.pi / 180;

  final a =
      math.sin(latDelta / 2) * math.sin(latDelta / 2) +
      math.cos(fromLat) *
          math.cos(toLat) *
          math.sin(lonDelta / 2) *
          math.sin(lonDelta / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

  return earthRadiusMeters * c;
}

String _formatDistance(double meters) {
  if (meters < 1000) {
    return '${meters.round()} m';
  }

  final kilometers = meters / 1000;
  if (kilometers < 10) {
    return '${kilometers.toStringAsFixed(1)} km';
  }

  return '${kilometers.round()} km';
}

Future<AdminDivision?> _lookupAdminDivision(LatLng position) async {
  final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
    'format': 'jsonv2',
    'lat': position.latitude.toStringAsFixed(6),
    'lon': position.longitude.toStringAsFixed(6),
    'addressdetails': '1',
    'accept-language': 'pl',
  });

  try {
    final response = await http
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 4));

    if (response.statusCode != 200) {
      return null;
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic>) {
      return null;
    }

    final address = payload['address'];
    if (address is! Map<String, dynamic>) {
      return null;
    }

    String valueOf(String key) => (address[key] as String?)?.trim() ?? '';
    final city = valueOf('city').isNotEmpty
        ? valueOf('city')
        : valueOf('town').isNotEmpty
        ? valueOf('town')
        : valueOf('village');

    return AdminDivision(
      province: valueOf('state'),
      county: valueOf('county').isNotEmpty ? valueOf('county') : city,
      municipality: valueOf('municipality').isNotEmpty
          ? valueOf('municipality')
          : valueOf('city_district').isNotEmpty
          ? valueOf('city_district')
          : city,
      city: city,
    );
  } catch (_) {
    return null;
  }
}

Future<AdminBoundary?> _lookupAdminBoundary({
  required VisitScope scope,
  required String areaName,
  LatLng? near,
}) async {
  final query = switch (scope) {
    VisitScope.province => '$areaName wojewodztwo Polska',
    VisitScope.county => '$areaName powiat Polska',
    VisitScope.municipality => '$areaName gmina Polska',
  };
  final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
    'format': 'jsonv2',
    'q': query,
    'addressdetails': '1',
    'polygon_geojson': '1',
    'limit': '8',
    'countrycodes': 'pl',
    'accept-language': 'pl',
  });

  try {
    final response = await http
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) {
      return null;
    }

    final payload = jsonDecode(response.body);
    if (payload is! List) {
      return null;
    }

    List<List<LatLng>> bestPolygons = const [];
    var bestScore = -1.0;

    for (final item in payload) {
      if (item is! Map<String, dynamic>) {
        continue;
      }

      final geojson = item['geojson'];
      final polygons = _polygonsFromGeoJson(geojson);
      if (polygons.isEmpty) {
        continue;
      }

      final score =
          _boundaryCandidateScore(item, scope, areaName, near) +
          _polygonWeight(polygons);
      if (score > bestScore) {
        bestScore = score;
        bestPolygons = polygons;
      }
    }

    if (bestPolygons.isEmpty) {
      return null;
    }

    return AdminBoundary(polygons: bestPolygons);
  } catch (_) {
    return null;
  }
}

double _boundaryCandidateScore(
  Map<String, dynamic> item,
  VisitScope scope,
  String areaName,
  LatLng? near,
) {
  var score = 0.0;
  final itemClass = (item['class'] as String?)?.toLowerCase() ?? '';
  final type = (item['type'] as String?)?.toLowerCase() ?? '';
  final displayName = (item['display_name'] as String?)?.toLowerCase() ?? '';
  final normalizedArea = areaName.toLowerCase();

  if (itemClass == 'boundary') {
    score += 20;
  }
  if (type == 'administrative') {
    score += 20;
  }
  if (displayName.contains(normalizedArea)) {
    score += 12;
  }

  final address = item['address'];
  if (address is Map<String, dynamic>) {
    final scopedAddress = switch (scope) {
      VisitScope.province => address['state'],
      VisitScope.county => address['county'],
      VisitScope.municipality => address['municipality'] ?? address['city'],
    };
    if ((scopedAddress as String?)?.toLowerCase().contains(normalizedArea) ??
        false) {
      score += 30;
    }
  }

  if (near != null) {
    final latitude = double.tryParse((item['lat'] as String?) ?? '');
    final longitude = double.tryParse((item['lon'] as String?) ?? '');
    if (latitude != null && longitude != null) {
      final distance = _distanceBetweenMeters(
        near,
        LatLng(latitude, longitude),
      );
      score += math.max(0, 20 - distance / 25000);
    }
  }

  return score;
}

double _polygonWeight(List<List<LatLng>> polygons) {
  final points = polygons.fold<int>(
    0,
    (total, polygon) => total + polygon.length,
  );
  return math.min(points / 200, 8);
}

List<List<LatLng>> _polygonsFromGeoJson(Object? geojson) {
  if (geojson is! Map<String, dynamic>) {
    return const [];
  }

  final type = geojson['type'];
  final coordinates = geojson['coordinates'];
  if (type == 'Polygon') {
    final polygon = _polygonOuterRing(coordinates);
    return polygon.isEmpty ? const [] : [polygon];
  }
  if (type == 'MultiPolygon' && coordinates is List) {
    final polygons = <List<LatLng>>[];
    for (final polygonCoordinates in coordinates) {
      final polygon = _polygonOuterRing(polygonCoordinates);
      if (polygon.isNotEmpty) {
        polygons.add(polygon);
      }
    }
    polygons.sort((a, b) => b.length.compareTo(a.length));
    return polygons.take(6).toList(growable: false);
  }

  return const [];
}

List<LatLng> _polygonOuterRing(Object? coordinates) {
  if (coordinates is! List || coordinates.isEmpty) {
    return const [];
  }

  final outerRing = coordinates.first;
  if (outerRing is! List) {
    return const [];
  }

  final points = <LatLng>[];
  for (final coordinate in outerRing) {
    if (coordinate is List && coordinate.length >= 2) {
      final longitude = (coordinate[0] as num?)?.toDouble();
      final latitude = (coordinate[1] as num?)?.toDouble();
      if (latitude != null && longitude != null) {
        points.add(LatLng(latitude, longitude));
      }
    }
  }

  return _thinPolygon(points, maxPoints: 700);
}

List<LatLng> _thinPolygon(List<LatLng> points, {required int maxPoints}) {
  if (points.length <= maxPoints) {
    return points;
  }

  final step = (points.length / maxPoints).ceil();
  final thinned = <LatLng>[];
  for (var index = 0; index < points.length; index += step) {
    thinned.add(points[index]);
  }
  if (thinned.first != points.last) {
    thinned.add(points.last);
  }

  return thinned;
}

enum VisitScope { province, county, municipality }

class WaypointMapScreen extends StatefulWidget {
  const WaypointMapScreen({super.key});

  @override
  State<WaypointMapScreen> createState() => _WaypointMapScreenState();
}

class _WaypointMapScreenState extends State<WaypointMapScreen> {
  static const _initialCenter = LatLng(52.2297, 21.0122);

  final List<Waypoint> _waypoints = [
    const Waypoint(
      id: 1,
      name: 'National Stadium',
      category: 'Match day',
      position: LatLng(52.2394, 21.0458),
      province: 'Mazowieckie',
      county: 'Warszawa',
      municipality: 'Warszawa',
      city: 'Warszawa',
      visited: true,
    ),
    const Waypoint(
      id: 2,
      name: 'Old Town meeting point',
      category: 'Walk',
      position: LatLng(52.2499, 21.0122),
      province: 'Mazowieckie',
      county: 'Warszawa',
      municipality: 'Warszawa',
      city: 'Warszawa',
    ),
    const Waypoint(
      id: 3,
      name: 'Riverside checkpoint',
      category: 'Route',
      position: LatLng(52.2356, 21.0314),
      province: 'Mazowieckie',
      county: 'Warszawa',
      municipality: 'Warszawa',
      city: 'Warszawa',
    ),
    const Waypoint(
      id: 4,
      name: 'Gdansk waterfront gate',
      category: 'Away trip',
      position: LatLng(54.3520, 18.6466),
      province: 'Pomorskie',
      county: 'Gdansk',
      municipality: 'Gdansk',
      city: 'Gdansk',
    ),
  ];

  int _nextWaypointId = 5;
  VisitScope _visitScope = VisitScope.province;

  String _scopeValue(Waypoint waypoint) {
    return switch (_visitScope) {
      VisitScope.province => waypoint.province.trim(),
      VisitScope.county => waypoint.county.trim(),
      VisitScope.municipality => waypoint.municipality.trim(),
    };
  }

  String _scopeDivisionValue(AdminDivision division) {
    return switch (_visitScope) {
      VisitScope.province => division.province.trim(),
      VisitScope.county => division.county.trim(),
      VisitScope.municipality => division.municipality.trim(),
    };
  }

  String get _scopeLabel {
    return switch (_visitScope) {
      VisitScope.province => 'Wojewodztwo',
      VisitScope.county => 'Powiat',
      VisitScope.municipality => 'Gmina',
    };
  }

  String get _activeAreaName {
    final selectedAreaName = _selectedWaypoint == null
        ? ''
        : _scopeValue(_selectedWaypoint!);
    if (selectedAreaName.isNotEmpty) {
      return selectedAreaName;
    }

    final focusedDivision = _focusedDivision;
    if (focusedDivision != null) {
      final focusedAreaName = _scopeDivisionValue(focusedDivision);
      if (focusedAreaName.isNotEmpty) {
        return focusedAreaName;
      }
    }

    for (final waypoint in _waypoints) {
      final value = _scopeValue(waypoint);
      if (value.isNotEmpty) {
        return value;
      }
    }

    return 'No area data';
  }

  Iterable<Waypoint> get _activeAreaWaypoints {
    final areaName = _activeAreaName;
    return _waypoints.where((waypoint) => _scopeValue(waypoint) == areaName);
  }

  List<List<LatLng>> get _activeAreaShapes {
    if (_activeBoundaryPolygons.isNotEmpty) {
      return _activeBoundaryPolygons;
    }

    final positions = _activeAreaWaypoints
        .map((waypoint) => waypoint.position)
        .toList(growable: false);
    if (positions.isNotEmpty) {
      return [_areaShapeAround(positions)];
    }

    final focusedPosition = _focusedPosition;
    if (focusedPosition != null) {
      return [
        _areaShapeAround([focusedPosition]),
      ];
    }

    return const [];
  }

  String get _activeBoundaryKey => '$_visitScope:$_activeAreaName';

  LatLng? get _activeAreaRepresentativePosition {
    final selectedWaypoint = _selectedWaypoint;
    if (selectedWaypoint != null) {
      return selectedWaypoint.position;
    }

    final focusedPosition = _focusedPosition;
    if (focusedPosition != null) {
      return focusedPosition;
    }

    final waypoints = _activeAreaWaypoints.toList(growable: false);
    if (waypoints.isEmpty) {
      return null;
    }

    final latitude =
        waypoints
            .map((waypoint) => waypoint.position.latitude)
            .reduce((sum, latitude) => sum + latitude) /
        waypoints.length;
    final longitude =
        waypoints
            .map((waypoint) => waypoint.position.longitude)
            .reduce((sum, longitude) => sum + longitude) /
        waypoints.length;

    return LatLng(latitude, longitude);
  }

  int get _areaVisitedCount =>
      _activeAreaWaypoints.where((waypoint) => waypoint.visited).length;

  int get _areaTotalCount => _activeAreaWaypoints.length;

  double get _progress {
    return _areaTotalCount == 0 ? 0 : _areaVisitedCount / _areaTotalCount;
  }

  Waypoint? _editingWaypoint;
  LatLng _draftPosition = _initialCenter;
  int _editorRevision = 0;
  int _adminLookupRevision = 0;
  bool _adminMode = false;
  bool _editorOpen = false;
  int? _selectedWaypointId;
  AdminDivision? _focusedDivision;
  LatLng? _focusedPosition;
  int _areaLookupRevision = 0;
  final Map<String, List<List<LatLng>>> _boundaryCache = {};
  List<List<LatLng>> _activeBoundaryPolygons = const [];
  String _loadedBoundaryKey = '';
  int _boundaryLookupRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refreshAreaBoundary();
      }
    });
  }

  Waypoint? get _selectedWaypoint {
    final id = _selectedWaypointId;
    if (id == null) {
      return null;
    }

    for (final waypoint in _waypoints) {
      if (waypoint.id == id) {
        return waypoint;
      }
    }

    return null;
  }

  void _startCreateAt(
    TapPosition _,
    LatLng position, {
    bool lookupAdmin = true,
  }) {
    if (!_adminMode) {
      _focusAreaAt(position);
      return;
    }

    setState(() {
      _editingWaypoint = null;
      _draftPosition = position;
      _editorOpen = true;
      _selectedWaypointId = null;
      _focusedDivision = null;
      _focusedPosition = null;
      _areaLookupRevision++;
      _editorRevision++;
      if (lookupAdmin) {
        _adminLookupRevision++;
      }
    });
  }

  void _setAdminMode(bool value) {
    setState(() {
      _adminMode = value;
      if (!_adminMode) {
        _editingWaypoint = null;
        _editorOpen = false;
        _editorRevision++;
      }
    });
  }

  void _addCenterWaypoint() {
    _startCreateAt(
      TapPosition(Offset.zero, Offset.zero),
      _initialCenter,
      lookupAdmin: false,
    );
  }

  void _editWaypoint(Waypoint waypoint) {
    setState(() {
      _editingWaypoint = waypoint;
      _draftPosition = waypoint.position;
      _editorOpen = true;
      _selectedWaypointId = waypoint.id;
      _editorRevision++;
    });
  }

  void _selectWaypoint(Waypoint waypoint) {
    setState(() {
      _selectedWaypointId = waypoint.id;
      _focusedPosition = null;
      _areaLookupRevision++;
    });
    _refreshAreaBoundary();
  }

  void _clearSelectedWaypoint() {
    setState(() {
      _selectedWaypointId = null;
    });
    _refreshAreaBoundary();
  }

  Future<void> _focusAreaAt(LatLng position) async {
    final lookupId = ++_areaLookupRevision;

    setState(() {
      _selectedWaypointId = null;
      _focusedDivision = null;
      _focusedPosition = position;
    });

    final division = await _lookupAdminDivision(position);
    if (!mounted || lookupId != _areaLookupRevision) {
      return;
    }

    setState(() {
      _focusedDivision = division;
    });
    _refreshAreaBoundary();
  }

  void _refreshAreaBoundary() {
    final areaName = _activeAreaName;
    if (areaName == 'No area data') {
      setState(() {
        _activeBoundaryPolygons = const [];
        _loadedBoundaryKey = '';
      });
      return;
    }

    final key = _activeBoundaryKey;
    final cached = _boundaryCache[key];
    if (cached != null) {
      setState(() {
        _activeBoundaryPolygons = cached;
        _loadedBoundaryKey = key;
      });
      return;
    }

    if (_loadedBoundaryKey == key && _activeBoundaryPolygons.isNotEmpty) {
      return;
    }

    final lookupId = ++_boundaryLookupRevision;
    final representativePosition = _activeAreaRepresentativePosition;
    if (_loadedBoundaryKey != key && _activeBoundaryPolygons.isNotEmpty) {
      setState(() {
        _activeBoundaryPolygons = const [];
        _loadedBoundaryKey = key;
      });
    }

    _lookupAdminBoundary(
      scope: _visitScope,
      areaName: areaName,
      near: representativePosition,
    ).then((boundary) {
      if (!mounted || lookupId != _boundaryLookupRevision) {
        return;
      }

      final polygons = boundary?.polygons ?? const <List<LatLng>>[];
      if (polygons.isNotEmpty) {
        _boundaryCache[key] = polygons;
      }

      setState(() {
        _activeBoundaryPolygons = polygons;
        _loadedBoundaryKey = key;
      });
    });
  }

  List<LatLng> _areaShapeAround(List<LatLng> positions) {
    final latitudes = positions.map((position) => position.latitude);
    final longitudes = positions.map((position) => position.longitude);
    final minLat = latitudes.reduce(math.min);
    final maxLat = latitudes.reduce(math.max);
    final minLon = longitudes.reduce(math.min);
    final maxLon = longitudes.reduce(math.max);
    final center = LatLng((minLat + maxLat) / 2, (minLon + maxLon) / 2);
    final paddingMeters = switch (_visitScope) {
      VisitScope.province => positions.length == 1 ? 18000.0 : 8500.0,
      VisitScope.county => positions.length == 1 ? 8500.0 : 4200.0,
      VisitScope.municipality => positions.length == 1 ? 3600.0 : 1800.0,
    };
    final latPadding = paddingMeters / 111320;
    final lonScale = math.cos(center.latitude * math.pi / 180).abs();
    final lonPadding = paddingMeters / (111320 * math.max(lonScale, 0.2));

    final west = minLon - lonPadding;
    final east = maxLon + lonPadding;
    final north = maxLat + latPadding;
    final south = minLat - latPadding;
    final midLat = center.latitude;
    final midLon = center.longitude;

    return [
      LatLng(north, midLon - (midLon - west) * 0.35),
      LatLng(north - (north - midLat) * 0.18, east),
      LatLng(midLat + (north - midLat) * 0.10, east - (east - midLon) * 0.08),
      LatLng(south + (midLat - south) * 0.22, east - (east - midLon) * 0.18),
      LatLng(south, midLon + (east - midLon) * 0.22),
      LatLng(south + (midLat - south) * 0.16, west),
      LatLng(midLat + (north - midLat) * 0.18, west + (midLon - west) * 0.06),
    ];
  }

  void _closeEditor() {
    setState(() {
      _editingWaypoint = null;
      _editorOpen = false;
      _editorRevision++;
    });
  }

  void _saveWaypoint({
    required int? id,
    required String name,
    required String category,
    required LatLng position,
    required String province,
    required String county,
    required String municipality,
    required String city,
    required bool visited,
  }) {
    late final int savedId;
    final shouldLookupAdmin =
        province.isEmpty &&
        county.isEmpty &&
        municipality.isEmpty &&
        city.isEmpty;

    setState(() {
      if (id == null) {
        final nextId = _nextWaypointId++;
        savedId = nextId;
        _waypoints.add(
          Waypoint(
            id: nextId,
            name: name,
            category: category,
            position: position,
            province: province,
            county: county,
            municipality: municipality,
            city: city,
            visited: visited,
          ),
        );
      } else {
        savedId = id;
        final index = _waypoints.indexWhere((item) => item.id == id);
        if (index != -1) {
          _waypoints[index] = _waypoints[index].copyWith(
            name: name,
            category: category,
            position: position,
            province: province,
            county: county,
            municipality: municipality,
            city: city,
            visited: visited,
          );
        }
      }

      _editingWaypoint = null;
      _draftPosition = position;
      _editorOpen = false;
      _selectedWaypointId = savedId;
      _editorRevision++;
    });
    _refreshAreaBoundary();

    if (shouldLookupAdmin) {
      _enrichWaypointAdminData(savedId, position);
    }
  }

  Future<void> _enrichWaypointAdminData(int id, LatLng position) async {
    final division = await _lookupAdminDivision(position);
    if (!mounted || division == null) {
      return;
    }

    setState(() {
      final index = _waypoints.indexWhere((item) => item.id == id);
      if (index == -1) {
        return;
      }

      final waypoint = _waypoints[index];
      if (waypoint.province.isNotEmpty ||
          waypoint.county.isNotEmpty ||
          waypoint.municipality.isNotEmpty ||
          waypoint.city.isNotEmpty) {
        return;
      }

      _waypoints[index] = waypoint.copyWith(
        province: division.province,
        county: division.county,
        municipality: division.municipality,
        city: division.city,
      );
    });
    _refreshAreaBoundary();
  }

  void _setVisitScope(VisitScope scope) {
    setState(() {
      _visitScope = scope;
    });
    _refreshAreaBoundary();
  }

  void _deleteWaypoint(Waypoint waypoint) {
    setState(() {
      _waypoints.removeWhere((item) => item.id == waypoint.id);
      if (_selectedWaypointId == waypoint.id) {
        _selectedWaypointId = null;
      }
      if (_editingWaypoint?.id == waypoint.id) {
        _editingWaypoint = null;
        _editorOpen = false;
        _editorRevision++;
      }
    });
    _refreshAreaBoundary();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: 13,
              onTap: _startCreateAt,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.pietrusiewicz.stadiumly',
              ),
              if (_activeAreaShapes.isNotEmpty)
                PolygonLayer(
                  polygons: [
                    for (final polygon in _activeAreaShapes)
                      Polygon(
                        points: polygon,
                        color: colors.primary.withValues(alpha: 0.14),
                        borderColor: colors.primary.withValues(alpha: 0.76),
                        borderStrokeWidth: 3,
                      ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  for (final waypoint in _waypoints)
                    Marker(
                      point: waypoint.position,
                      width: 54,
                      height: 54,
                      child: _WaypointMarker(
                        waypoint: waypoint,
                        selected: _selectedWaypointId == waypoint.id,
                        onPressed: () => _selectWaypoint(waypoint),
                      ),
                    ),
                  if (_adminMode && _editorOpen)
                    Marker(
                      point: _draftPosition,
                      width: 62,
                      height: 62,
                      child: const _DraftWaypointMarker(),
                    ),
                ],
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _TripSummary(
                areaName: _activeAreaName,
                selectedWaypoint: _selectedWaypoint,
                scopeLabel: _scopeLabel,
                scope: _visitScope,
                visitedCount: _areaVisitedCount,
                totalCount: _areaTotalCount,
                progress: _progress,
                onScopeChanged: _setVisitScope,
                onClearSelection: _clearSelectedWaypoint,
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _WaypointPanel(
                waypoints: _waypoints,
                distanceOrigin: _initialCenter,
                adminMode: _adminMode,
                editorOpen: _editorOpen,
                editingWaypoint: _editingWaypoint,
                selectedWaypointId: _selectedWaypointId,
                draftPosition: _draftPosition,
                editorRevision: _editorRevision,
                adminLookupRevision: _adminLookupRevision,
                onAdminModeChanged: _setAdminMode,
                onAddWaypoint: _addCenterWaypoint,
                onCloseEditor: _closeEditor,
                onEdit: _editWaypoint,
                onSave: _saveWaypoint,
                onSelect: _selectWaypoint,
                onDelete: _deleteWaypoint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TripSummary extends StatelessWidget {
  const _TripSummary({
    required this.areaName,
    required this.selectedWaypoint,
    required this.scopeLabel,
    required this.scope,
    required this.visitedCount,
    required this.totalCount,
    required this.progress,
    required this.onScopeChanged,
    required this.onClearSelection,
  });

  final String areaName;
  final Waypoint? selectedWaypoint;
  final String scopeLabel;
  final VisitScope scope;
  final int visitedCount;
  final int totalCount;
  final double progress;
  final ValueChanged<VisitScope> onScopeChanged;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final waypoint = selectedWaypoint;
    final title = waypoint?.name ?? areaName;
    final subtitle = waypoint == null
        ? 'Visited in $scopeLabel'
        : '${waypoint.category} - ${waypoint.visited ? 'visited' : 'not visited'}';
    final detail = waypoint == null
        ? null
        : '$areaName - '
              '${waypoint.position.latitude.toStringAsFixed(4)}, '
              '${waypoint.position.longitude.toStringAsFixed(4)}';

    return Material(
      elevation: 6,
      color: colors.surface,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: colors.shadow.withValues(alpha: 0.12),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(5),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: waypoint == null
                        ? _AreaShapeIcon(
                            key: ValueKey('area-shape-$scope-$areaName'),
                            scope: scope,
                            areaName: areaName,
                          )
                        : _ObjectShapeIcon(
                            key: ValueKey('object-shape-${waypoint.id}'),
                            waypoint: waypoint,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (detail != null)
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
                if (waypoint == null)
                  Text(
                    '$visitedCount/$totalCount',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                if (waypoint != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Clear selected object',
                    onPressed: onClearSelection,
                    constraints: const BoxConstraints.tightFor(
                      width: 34,
                      height: 34,
                    ),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ],
            ),
            if (waypoint == null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<VisitScope>(
                      segments: const [
                        ButtonSegment(
                          value: VisitScope.province,
                          label: Text('Woj'),
                        ),
                        ButtonSegment(
                          value: VisitScope.county,
                          label: Text('Powiat'),
                        ),
                        ButtonSegment(
                          value: VisitScope.municipality,
                          label: Text('Gmina'),
                        ),
                      ],
                      selected: {scope},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) {
                        onScopeChanged(selection.single);
                      },
                    ),
                  ),
                ],
              ),
            ],
            if (waypoint == null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: progress,
                  backgroundColor: colors.surfaceContainerHighest,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ObjectShapeIcon extends StatelessWidget {
  const _ObjectShapeIcon({super.key, required this.waypoint});

  final Waypoint waypoint;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fillColor = waypoint.visited
        ? colors.primary
        : Colors.deepOrangeAccent;

    return SizedBox.expand(
      child: CustomPaint(
        painter: _ObjectShapePainter(
          fillColor: fillColor,
          strokeColor: colors.onPrimaryContainer,
          visited: waypoint.visited,
        ),
      ),
    );
  }
}

class _ObjectShapePainter extends CustomPainter {
  const _ObjectShapePainter({
    required this.fillColor,
    required this.strokeColor,
    required this.visited,
  });

  final Color fillColor;
  final Color strokeColor;
  final bool visited;

  @override
  void paint(Canvas canvas, Size size) {
    Offset at(double dx, double dy) =>
        Offset(dx * size.width, dy * size.height);

    final shape = ui.Path()
      ..moveTo(at(0.50, 0.04).dx, at(0.50, 0.04).dy)
      ..cubicTo(
        at(0.77, 0.05).dx,
        at(0.77, 0.05).dy,
        at(0.88, 0.48).dx,
        at(0.88, 0.48).dy,
        at(0.72, 0.70).dx,
        at(0.72, 0.70).dy,
      )
      ..lineTo(at(0.50, 0.95).dx, at(0.50, 0.95).dy)
      ..lineTo(at(0.28, 0.70).dx, at(0.28, 0.70).dy)
      ..cubicTo(
        at(0.12, 0.48).dx,
        at(0.12, 0.48).dy,
        at(0.06, 0.23).dx,
        at(0.06, 0.23).dy,
        at(0.50, 0.04).dx,
        at(0.50, 0.04).dy,
      )
      ..close();

    canvas.drawPath(
      shape.shift(const Offset(0, 1)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.16)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      shape,
      Paint()
        ..shader =
            ui.Gradient.linear(Offset.zero, Offset(size.width, size.height), [
              fillColor.withValues(alpha: 0.98),
              Color.lerp(fillColor, Colors.black, 0.24)!,
            ])
        ..style = PaintingStyle.fill,
    );

    final ring = Rect.fromCenter(
      center: at(0.50, 0.39),
      width: size.width * 0.45,
      height: size.height * 0.29,
    );
    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawOval(ring, ringPaint);
    canvas.drawOval(ring.deflate(size.shortestSide * 0.06), ringPaint);

    if (visited) {
      final check = ui.Path()
        ..moveTo(at(0.35, 0.40).dx, at(0.35, 0.40).dy)
        ..lineTo(at(0.46, 0.51).dx, at(0.46, 0.51).dy)
        ..lineTo(at(0.67, 0.30).dx, at(0.67, 0.30).dy);
      canvas.drawPath(
        check,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
    }

    canvas.drawPath(
      shape,
      Paint()
        ..color = strokeColor.withValues(alpha: 0.58)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _ObjectShapePainter oldDelegate) {
    return oldDelegate.fillColor != fillColor ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.visited != visited;
  }
}

class _AreaShapeIcon extends StatelessWidget {
  const _AreaShapeIcon({
    super.key,
    required this.scope,
    required this.areaName,
  });

  final VisitScope scope;
  final String areaName;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SizedBox.expand(
      child: CustomPaint(
        painter: _AreaShapePainter(
          scope: scope,
          areaName: areaName,
          fillColor: colors.primary,
          strokeColor: colors.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _AreaShapePainter extends CustomPainter {
  const _AreaShapePainter({
    required this.scope,
    required this.areaName,
    required this.fillColor,
    required this.strokeColor,
  });

  final VisitScope scope;
  final String areaName;
  final Color fillColor;
  final Color strokeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = _shapeFor(scope, areaName);
    final path = _smoothedPath(shape, size);

    final shadowPath = path.shift(const Offset(0, 1));
    canvas.drawPath(
      shadowPath,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader =
            ui.Gradient.linear(Offset.zero, Offset(size.width, size.height), [
              fillColor.withValues(alpha: 0.98),
              Color.lerp(fillColor, Colors.black, 0.18)!,
            ])
        ..style = PaintingStyle.fill,
    );

    canvas.save();
    canvas.clipPath(path);
    _drawMapDetails(canvas, size);
    canvas.restore();

    canvas.drawPath(
      path,
      Paint()
        ..color = strokeColor.withValues(alpha: 0.58)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  ui.Path _smoothedPath(List<Offset> shape, Size size) {
    Offset scaled(Offset point) {
      return Offset(point.dx * size.width, point.dy * size.height);
    }

    final points = shape.map(scaled).toList();
    final path = ui.Path();
    final first = Offset.lerp(points.last, points.first, 0.5)!;
    path.moveTo(first.dx, first.dy);

    for (var index = 0; index < points.length; index++) {
      final current = points[index];
      final next = points[(index + 1) % points.length];
      final midpoint = Offset.lerp(current, next, 0.5)!;
      path.quadraticBezierTo(current.dx, current.dy, midpoint.dx, midpoint.dy);
    }

    path.close();
    return path;
  }

  void _drawMapDetails(Canvas canvas, Size size) {
    Offset at(double dx, double dy) =>
        Offset(dx * size.width, dy * size.height);

    final boundaryPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    switch (scope) {
      case VisitScope.province:
        canvas.drawLine(at(0.18, 0.40), at(0.84, 0.56), boundaryPaint);
        canvas.drawLine(at(0.43, 0.12), at(0.35, 0.89), boundaryPaint);
        canvas.drawLine(at(0.23, 0.73), at(0.76, 0.31), boundaryPaint);
      case VisitScope.county:
        canvas.drawLine(at(0.22, 0.31), at(0.80, 0.31), boundaryPaint);
        canvas.drawLine(at(0.20, 0.55), at(0.82, 0.55), boundaryPaint);
        canvas.drawLine(at(0.40, 0.16), at(0.40, 0.83), boundaryPaint);
        canvas.drawLine(at(0.63, 0.19), at(0.58, 0.86), boundaryPaint);
      case VisitScope.municipality:
        canvas.drawLine(at(0.25, 0.44), at(0.75, 0.38), boundaryPaint);
        canvas.drawLine(at(0.35, 0.22), at(0.61, 0.80), boundaryPaint);
    }

    final routePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.42)
      ..strokeWidth = switch (scope) {
        VisitScope.province => 1.45,
        VisitScope.county => 1.3,
        VisitScope.municipality => 1.15,
      }
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final route = ui.Path()
      ..moveTo(at(0.19, 0.67).dx, at(0.19, 0.67).dy)
      ..cubicTo(
        at(0.35, 0.53).dx,
        at(0.35, 0.53).dy,
        at(0.43, 0.77).dx,
        at(0.43, 0.77).dy,
        at(0.58, 0.60).dx,
        at(0.58, 0.60).dy,
      )
      ..cubicTo(
        at(0.70, 0.47).dx,
        at(0.70, 0.47).dy,
        at(0.60, 0.29).dx,
        at(0.60, 0.29).dy,
        at(0.80, 0.22).dx,
        at(0.80, 0.22).dy,
      );
    canvas.drawPath(route, routePaint);

    final glowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(at(0.58, 0.60), size.shortestSide * 0.12, glowPaint);

    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final points = switch (scope) {
      VisitScope.province => [at(0.19, 0.67), at(0.58, 0.60), at(0.80, 0.22)],
      VisitScope.county => [at(0.28, 0.34), at(0.58, 0.60), at(0.72, 0.42)],
      VisitScope.municipality => [at(0.58, 0.60)],
    };
    for (final point in points) {
      canvas.drawCircle(point, size.shortestSide * 0.035, dotPaint);
    }

    final stadiumCenter = at(0.60, 0.60);
    final stadiumRect = Rect.fromCenter(
      center: stadiumCenter,
      width: size.width * 0.29,
      height: size.height * 0.19,
    );
    final stadiumPaint = Paint()
      ..color = strokeColor.withValues(alpha: 0.86)
      ..strokeWidth = 1.35
      ..style = PaintingStyle.stroke;
    canvas.drawOval(stadiumRect, stadiumPaint);
    canvas.drawOval(
      stadiumRect.deflate(size.shortestSide * 0.045),
      stadiumPaint,
    );
  }

  List<Offset> _shapeFor(VisitScope scope, String areaName) {
    final normalized = areaName.toLowerCase();

    if (scope == VisitScope.province && normalized.contains('mazowieck')) {
      return const [
        Offset(0.34, 0.04),
        Offset(0.57, 0.09),
        Offset(0.72, 0.22),
        Offset(0.90, 0.39),
        Offset(0.78, 0.55),
        Offset(0.82, 0.78),
        Offset(0.55, 0.94),
        Offset(0.40, 0.80),
        Offset(0.18, 0.86),
        Offset(0.08, 0.62),
        Offset(0.20, 0.45),
        Offset(0.14, 0.24),
      ];
    }

    if (normalized.contains('warszawa')) {
      return switch (scope) {
        VisitScope.county => const [
          Offset(0.42, 0.05),
          Offset(0.72, 0.12),
          Offset(0.87, 0.36),
          Offset(0.77, 0.66),
          Offset(0.54, 0.91),
          Offset(0.30, 0.82),
          Offset(0.12, 0.56),
          Offset(0.20, 0.24),
        ],
        VisitScope.municipality => const [
          Offset(0.50, 0.04),
          Offset(0.74, 0.17),
          Offset(0.91, 0.48),
          Offset(0.70, 0.83),
          Offset(0.42, 0.95),
          Offset(0.12, 0.70),
          Offset(0.16, 0.30),
        ],
        VisitScope.province => const [
          Offset(0.24, 0.12),
          Offset(0.72, 0.10),
          Offset(0.88, 0.44),
          Offset(0.58, 0.90),
          Offset(0.18, 0.74),
        ],
      };
    }

    return switch (scope) {
      VisitScope.province => const [
        Offset(0.24, 0.08),
        Offset(0.70, 0.12),
        Offset(0.91, 0.45),
        Offset(0.63, 0.91),
        Offset(0.16, 0.78),
        Offset(0.09, 0.34),
      ],
      VisitScope.county => const [
        Offset(0.33, 0.09),
        Offset(0.78, 0.18),
        Offset(0.87, 0.62),
        Offset(0.52, 0.93),
        Offset(0.13, 0.63),
        Offset(0.18, 0.27),
      ],
      VisitScope.municipality => const [
        Offset(0.50, 0.06),
        Offset(0.85, 0.34),
        Offset(0.73, 0.83),
        Offset(0.28, 0.88),
        Offset(0.10, 0.38),
      ],
    };
  }

  @override
  bool shouldRepaint(covariant _AreaShapePainter oldDelegate) {
    return oldDelegate.scope != scope ||
        oldDelegate.areaName != areaName ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.strokeColor != strokeColor;
  }
}

class _WaypointMarker extends StatelessWidget {
  const _WaypointMarker({
    required this.waypoint,
    required this.selected,
    required this.onPressed,
  });

  final Waypoint waypoint;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = waypoint.visited
        ? Theme.of(context).colorScheme.primary
        : Colors.deepOrangeAccent;

    return Tooltip(
      message: waypoint.name,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: selected ? 14 : 10,
                offset: Offset(0, selected ? 6 : 4),
              ),
            ],
          ),
          padding: EdgeInsets.all(selected ? 3 : 5),
          child: CircleAvatar(
            backgroundColor: color,
            radius: selected ? 23 : null,
            child: Icon(
              waypoint.visited ? Icons.check : Icons.place,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _DraftWaypointMarker extends StatelessWidget {
  const _DraftWaypointMarker();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Tooltip(
      message: 'Selected location',
      child: Container(
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.24),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        padding: const EdgeInsets.all(7),
        child: CircleAvatar(
          backgroundColor: colors.primary,
          child: const Icon(Icons.add_location_alt, color: Colors.white),
        ),
      ),
    );
  }
}

typedef _WaypointSave =
    void Function({
      required int? id,
      required String name,
      required String category,
      required LatLng position,
      required String province,
      required String county,
      required String municipality,
      required String city,
      required bool visited,
    });

class _WaypointPanel extends StatefulWidget {
  const _WaypointPanel({
    required this.waypoints,
    required this.distanceOrigin,
    required this.adminMode,
    required this.editorOpen,
    required this.editingWaypoint,
    required this.selectedWaypointId,
    required this.draftPosition,
    required this.editorRevision,
    required this.adminLookupRevision,
    required this.onAdminModeChanged,
    required this.onAddWaypoint,
    required this.onCloseEditor,
    required this.onEdit,
    required this.onSave,
    required this.onSelect,
    required this.onDelete,
  });

  final List<Waypoint> waypoints;
  final LatLng distanceOrigin;
  final bool adminMode;
  final bool editorOpen;
  final Waypoint? editingWaypoint;
  final int? selectedWaypointId;
  final LatLng draftPosition;
  final int editorRevision;
  final int adminLookupRevision;
  final ValueChanged<bool> onAdminModeChanged;
  final VoidCallback onAddWaypoint;
  final VoidCallback onCloseEditor;
  final ValueChanged<Waypoint> onEdit;
  final _WaypointSave onSave;
  final ValueChanged<Waypoint> onSelect;
  final ValueChanged<Waypoint> onDelete;

  @override
  State<_WaypointPanel> createState() => _WaypointPanelState();
}

class _WaypointPanelState extends State<_WaypointPanel> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _provinceController = TextEditingController();
  final _countyController = TextEditingController();
  final _municipalityController = TextEditingController();
  final _cityController = TextEditingController();

  int? _activeId;
  int _loadedRevision = -1;
  int _lookupRevision = 0;
  bool _visited = false;
  bool _adminLookupPending = false;

  @override
  void initState() {
    super.initState();
    _loadEditor();
  }

  @override
  void didUpdateWidget(covariant _WaypointPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editorRevision != widget.editorRevision) {
      _loadEditor();
    }
    if (oldWidget.adminLookupRevision != widget.adminLookupRevision) {
      _refreshAdminFields(force: true);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _provinceController.dispose();
    _countyController.dispose();
    _municipalityController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  void _loadEditor() {
    final waypoint = widget.editingWaypoint;

    _activeId = waypoint?.id;
    _visited = waypoint?.visited ?? false;
    _nameController.text = waypoint?.name ?? '';
    _categoryController.text = waypoint?.category ?? '';
    _latitudeController.text = (waypoint?.position ?? widget.draftPosition)
        .latitude
        .toStringAsFixed(6);
    _longitudeController.text = (waypoint?.position ?? widget.draftPosition)
        .longitude
        .toStringAsFixed(6);
    _provinceController.text = waypoint?.province ?? '';
    _countyController.text = waypoint?.county ?? '';
    _municipalityController.text = waypoint?.municipality ?? '';
    _cityController.text = waypoint?.city ?? '';
    _loadedRevision = widget.editorRevision;
  }

  double? _coordinateFrom(String value) {
    return double.tryParse(value.trim().replaceAll(',', '.'));
  }

  String? _requiredText(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }

    return null;
  }

  String? _latitudeError(String? value) {
    final parsed = _coordinateFrom(value ?? '');
    if (parsed == null) {
      return 'Enter latitude';
    }
    if (parsed < -90 || parsed > 90) {
      return 'Use -90 to 90';
    }

    return null;
  }

  String? _longitudeError(String? value) {
    final parsed = _coordinateFrom(value ?? '');
    if (parsed == null) {
      return 'Enter longitude';
    }
    if (parsed < -180 || parsed > 180) {
      return 'Use -180 to 180';
    }

    return null;
  }

  bool get _adminFieldsEmpty {
    return _provinceController.text.trim().isEmpty &&
        _countyController.text.trim().isEmpty &&
        _municipalityController.text.trim().isEmpty &&
        _cityController.text.trim().isEmpty;
  }

  LatLng? _positionFromForm() {
    final latitude = _coordinateFrom(_latitudeController.text);
    final longitude = _coordinateFrom(_longitudeController.text);
    if (latitude == null || longitude == null) {
      return null;
    }

    return LatLng(latitude, longitude);
  }

  void _applyAdminDivision(AdminDivision division, {required bool force}) {
    void apply(TextEditingController controller, String value) {
      if (force || controller.text.trim().isEmpty) {
        controller.text = value;
      }
    }

    apply(_provinceController, division.province);
    apply(_countyController, division.county);
    apply(_municipalityController, division.municipality);
    apply(_cityController, division.city);
  }

  Future<void> _refreshAdminFields({bool force = false}) async {
    final position = _positionFromForm();
    if (position == null || (!force && !_adminFieldsEmpty)) {
      return;
    }

    final lookupId = ++_lookupRevision;
    setState(() {
      _adminLookupPending = true;
    });

    final division = await _lookupAdminDivision(position);
    if (!mounted || lookupId != _lookupRevision) {
      return;
    }

    setState(() {
      if (division != null) {
        _applyAdminDivision(division, force: force);
      }
      _adminLookupPending = false;
    });
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    widget.onSave(
      id: _activeId,
      name: _nameController.text.trim(),
      category: _categoryController.text.trim(),
      position: LatLng(
        _coordinateFrom(_latitudeController.text)!,
        _coordinateFrom(_longitudeController.text)!,
      ),
      province: _provinceController.text.trim(),
      county: _countyController.text.trim(),
      municipality: _municipalityController.text.trim(),
      city: _cityController.text.trim(),
      visited: _visited,
    );
  }

  InputDecoration _compactDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }

  String get _adminSummaryText {
    final values = [
      _provinceController.text.trim(),
      _countyController.text.trim(),
      _municipalityController.text.trim(),
      _cityController.text.trim(),
    ].where((value) => value.isNotEmpty).toList();

    if (values.isEmpty) {
      return 'Will be added after save';
    }

    return values.join(' / ');
  }

  Widget _buildEditorForm(bool isEditing, ColorScheme colors) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isEditing ? 'Edit object' : 'Create object',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  _loadedRevision == widget.editorRevision
                      ? 'Tap map or enter lat/lon'
                      : '',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Close editor',
                  onPressed: widget.onCloseEditor,
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 36,
                  ),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final nameField = TextFormField(
                  controller: _nameController,
                  decoration: _compactDecoration('Name'),
                  validator: _requiredText,
                );
                final categoryField = TextFormField(
                  controller: _categoryController,
                  decoration: _compactDecoration('Category'),
                  validator: _requiredText,
                );

                if (constraints.maxWidth < 480) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      nameField,
                      const SizedBox(height: 8),
                      categoryField,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: nameField),
                    const SizedBox(width: 10),
                    Expanded(child: categoryField),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _latitudeController,
                    decoration: _compactDecoration('Latitude'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    validator: _latitudeError,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _longitudeController,
                    decoration: _compactDecoration('Longitude'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    validator: _longitudeError,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _adminLookupPending
                        ? 'Loading administrative data...'
                        : 'Admin: $_adminSummaryText',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh administrative data',
                  onPressed: _adminLookupPending
                      ? null
                      : () => _refreshAdminFields(force: true),
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                  icon: _adminLookupPending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.travel_explore, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Checkbox(
                  value: _visited,
                  onChanged: (value) {
                    setState(() {
                      _visited = value ?? false;
                    });
                  },
                ),
                const Expanded(child: Text('Visited')),
                FilledButton.icon(
                  onPressed: _save,
                  icon: Icon(isEditing ? Icons.save : Icons.add),
                  label: Text(isEditing ? 'Update' : 'Create'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaypointList() {
    if (widget.waypoints.isEmpty) {
      return const Center(child: Text('No objects yet'));
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      itemCount: widget.waypoints.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final waypoint = widget.waypoints[index];

        return _WaypointTile(
          waypoint: waypoint,
          distanceOrigin: widget.distanceOrigin,
          adminMode: widget.adminMode,
          selected: widget.selectedWaypointId == waypoint.id,
          onSelect: () => widget.onSelect(waypoint),
          onEdit: () => widget.onEdit(waypoint),
          onDelete: () => widget.onDelete(waypoint),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isEditing = _activeId != null;

    return Material(
      elevation: 10,
      color: colors.surface,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 300),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Waypoints',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${widget.waypoints.length} objects',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(width: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.person_outline, size: 18),
                        label: Text('User'),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.admin_panel_settings, size: 18),
                        label: Text('Admin'),
                      ),
                    ],
                    selected: {widget.adminMode},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) {
                      widget.onAdminModeChanged(selection.single);
                    },
                  ),
                  if (widget.adminMode) ...[
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: widget.onAddWaypoint,
                      icon: const Icon(Icons.add_location_alt, size: 18),
                      label: const Text('New'),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: widget.adminMode && widget.editorOpen
                  ? _buildEditorForm(isEditing, colors)
                  : _buildWaypointList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaypointTile extends StatelessWidget {
  const _WaypointTile({
    required this.waypoint,
    required this.distanceOrigin,
    required this.adminMode,
    required this.selected,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  final Waypoint waypoint;
  final LatLng distanceOrigin;
  final bool adminMode;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final distanceText = _formatDistance(
      _distanceBetweenMeters(distanceOrigin, waypoint.position),
    );

    return ListTile(
      selected: selected,
      selectedTileColor: colors.primaryContainer.withValues(alpha: 0.36),
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      onTap: onSelect,
      minLeadingWidth: 0,
      title: Row(
        children: [
          Expanded(
            child: Text(
              waypoint.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            distanceText,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      trailing: adminMode
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Edit object',
                  onPressed: onEdit,
                  color: colors.onSurfaceVariant,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Delete object',
                  onPressed: onDelete,
                  color: colors.onSurfaceVariant,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            )
          : null,
    );
  }
}
