import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const _outputPath = 'assets/admin_boundaries/wojewodztwa_poc.geojson';
const _userAgent = 'stadiumly-admin-boundary-generator/0.1';
const _simplifyToleranceDegrees = 0.0025;

const _boundarySpecs = [
  _BoundarySpec(
    name: 'Dolnoslaskie',
    type: 'province',
    query: 'wojewodztwo dolnoslaskie Polska',
    expectedAdminLevel: 4,
  ),
  _BoundarySpec(
    name: 'Kujawsko-pomorskie',
    type: 'province',
    query: 'wojewodztwo kujawsko-pomorskie Polska',
    expectedAdminLevel: 4,
  ),
  _BoundarySpec(
    name: 'Lubelskie',
    type: 'province',
    query: 'wojewodztwo lubelskie Polska',
    expectedAdminLevel: 4,
  ),
  _BoundarySpec(
    name: 'Lubuskie',
    type: 'province',
    query: 'wojewodztwo lubuskie Polska',
    expectedAdminLevel: 4,
  ),
  _BoundarySpec(
    name: 'Lodzkie',
    type: 'province',
    query: 'wojewodztwo lodzkie Polska',
    expectedAdminLevel: 4,
  ),
  _BoundarySpec(
    name: 'Malopolskie',
    type: 'province',
    query: 'wojewodztwo malopolskie Polska',
    expectedAdminLevel: 4,
  ),
  _BoundarySpec(
    name: 'Mazowieckie',
    type: 'province',
    query: 'wojewodztwo mazowieckie Polska',
    expectedAdminLevel: 4,
  ),
  _BoundarySpec(
    name: 'Opolskie',
    type: 'province',
    query: 'wojewodztwo opolskie Polska',
    expectedAdminLevel: 4,
  ),
  _BoundarySpec(
    name: 'Podkarpackie',
    type: 'province',
    query: 'wojewodztwo podkarpackie Polska',
    expectedAdminLevel: 4,
  ),
  _BoundarySpec(
    name: 'Podlaskie',
    type: 'province',
    query: 'wojewodztwo podlaskie Polska',
    expectedAdminLevel: 4,
  ),
  _BoundarySpec(
    name: 'Pomorskie',
    type: 'province',
    query: 'wojewodztwo pomorskie Polska',
    expectedAdminLevel: 4,
  ),
  _BoundarySpec(
    name: 'Slaskie',
    type: 'province',
    query: 'wojewodztwo slaskie Polska',
    expectedAdminLevel: 4,
  ),
  _BoundarySpec(
    name: 'Swietokrzyskie',
    type: 'province',
    query: 'wojewodztwo swietokrzyskie Polska',
    expectedAdminLevel: 4,
  ),
  _BoundarySpec(
    name: 'Warminsko-mazurskie',
    type: 'province',
    query: 'wojewodztwo warminsko-mazurskie Polska',
    expectedAdminLevel: 4,
  ),
  _BoundarySpec(
    name: 'Wielkopolskie',
    type: 'province',
    query: 'wojewodztwo wielkopolskie Polska',
    expectedAdminLevel: 4,
  ),
  _BoundarySpec(
    name: 'Zachodniopomorskie',
    type: 'province',
    query: 'wojewodztwo zachodniopomorskie Polska',
    expectedAdminLevel: 4,
  ),
  _BoundarySpec(
    name: 'Warszawa',
    type: 'county',
    query: 'miasto stołeczne Warszawa Polska',
    expectedAdminLevel: 6,
  ),
  _BoundarySpec(
    name: 'Warszawa',
    type: 'municipality',
    query: 'miasto stołeczne Warszawa Polska',
    expectedAdminLevel: 7,
  ),
  _BoundarySpec(
    name: 'Gdansk',
    type: 'county',
    query: 'Gdańsk Polska',
    expectedAdminLevel: 6,
  ),
  _BoundarySpec(
    name: 'Gdansk',
    type: 'municipality',
    query: 'miasto Gdańsk województwo pomorskie Polska',
    expectedAdminLevel: 8,
  ),
];

class _BoundarySpec {
  const _BoundarySpec({
    required this.name,
    required this.type,
    required this.query,
    required this.expectedAdminLevel,
  });

  final String name;
  final String type;
  final String query;
  final int expectedAdminLevel;
}

Future<void> main(List<String> args) async {
  final client = HttpClient();
  final features = <Map<String, Object?>>[];

  try {
    for (final spec in _boundarySpecs) {
      stdout.writeln('Fetching ${spec.type} ${spec.name}...');
      final feature = await _fetchBoundaryFeature(client, spec);
      features.add(feature);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
    }
  } finally {
    client.close(force: true);
  }

  final output = {
    'type': 'FeatureCollection',
    'name': 'admin_boundaries_osm',
    'generator': 'tool/generate_admin_boundaries.dart',
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'features': features,
  };

  final file = File(_outputPath);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(output),
    flush: true,
  );

  stdout.writeln('Wrote ${features.length} boundaries to $_outputPath');
}

Future<Map<String, Object?>> _fetchBoundaryFeature(
  HttpClient client,
  _BoundarySpec spec,
) async {
  final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
    'format': 'jsonv2',
    'q': spec.query,
    'addressdetails': '1',
    'extratags': '1',
    'dedupe': '1',
    'polygon_geojson': '1',
    'limit': '10',
    'countrycodes': 'pl',
    'accept-language': 'pl',
  });

  final request = await client.getUrl(uri);
  request.headers.set(HttpHeaders.acceptHeader, 'application/json');
  request.headers.set(HttpHeaders.userAgentHeader, _userAgent);

  final response = await request.close().timeout(const Duration(seconds: 30));
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode != HttpStatus.ok) {
    throw StateError(
      'Nominatim returned ${response.statusCode} for ${spec.name}: $body',
    );
  }

  final payload = jsonDecode(body);
  if (payload is! List) {
    throw StateError('Unexpected Nominatim payload for ${spec.name}');
  }

  Map<String, dynamic>? bestItem;
  var bestScore = double.negativeInfinity;
  for (final item in payload) {
    if (item is! Map<String, dynamic>) {
      continue;
    }

    final geometry = item['geojson'];
    if (!_isPolygonGeometry(geometry)) {
      continue;
    }

    final score = _scoreCandidate(item, spec);
    if (score > bestScore) {
      bestScore = score;
      bestItem = item;
    }
  }

  if (bestItem == null) {
    throw StateError('No OSM boundary geometry found for ${spec.name}');
  }

  final extratags = bestItem['extratags'];
  return {
    'type': 'Feature',
    'properties': {
      'name': spec.name,
      'type': spec.type,
      'source': 'OpenStreetMap via Nominatim',
      'osm_type': bestItem['osm_type'],
      'osm_id': bestItem['osm_id'],
      'admin_level': extratags is Map ? extratags['admin_level'] : null,
      'display_name': bestItem['display_name'],
    },
    'geometry': _simplifyGeometry(bestItem['geojson']),
  };
}

bool _isPolygonGeometry(Object? geometry) {
  if (geometry is! Map<String, dynamic>) {
    return false;
  }

  final type = geometry['type'];
  return type == 'Polygon' || type == 'MultiPolygon';
}

double _scoreCandidate(Map<String, dynamic> item, _BoundarySpec spec) {
  var score = 0.0;
  final itemClass = (item['class'] as String?)?.toLowerCase() ?? '';
  final type = (item['type'] as String?)?.toLowerCase() ?? '';
  final osmType = (item['osm_type'] as String?)?.toLowerCase() ?? '';
  final displayName = _normalizeName(item['display_name'] as String?);
  final normalizedName = _normalizeName(spec.name);

  if (itemClass == 'boundary') {
    score += 30;
  }
  if (type == 'administrative') {
    score += 30;
  }
  if (osmType == 'relation') {
    score += 20;
  }
  if (displayName.contains(normalizedName)) {
    score += 20;
  }

  final extratags = item['extratags'];
  final adminLevel = extratags is Map
      ? int.tryParse((extratags['admin_level'] as String?) ?? '')
      : null;
  if (adminLevel == spec.expectedAdminLevel) {
    score += 50;
  } else if (adminLevel != null) {
    score -= (adminLevel - spec.expectedAdminLevel).abs() * 10;
  }

  final rawImportance = item['importance'];
  final importance = rawImportance is num
      ? rawImportance.toDouble()
      : double.tryParse((rawImportance as String?) ?? '');
  if (importance != null) {
    score += math.min(importance * 10, 10);
  }

  return score;
}

String _normalizeName(String? value) {
  return (value ?? '')
      .toLowerCase()
      .replaceAll('ą', 'a')
      .replaceAll('ć', 'c')
      .replaceAll('ę', 'e')
      .replaceAll('ł', 'l')
      .replaceAll('ń', 'n')
      .replaceAll('ó', 'o')
      .replaceAll('ś', 's')
      .replaceAll('ż', 'z')
      .replaceAll('ź', 'z');
}

Map<String, dynamic> _simplifyGeometry(Object? geometry) {
  if (geometry is! Map<String, dynamic>) {
    throw StateError('Cannot simplify missing geometry');
  }

  final type = geometry['type'];
  final coordinates = geometry['coordinates'];
  if (type == 'Polygon' && coordinates is List) {
    return {
      'type': 'Polygon',
      'coordinates': _simplifyPolygonCoordinates(coordinates),
    };
  }
  if (type == 'MultiPolygon' && coordinates is List) {
    return {
      'type': 'MultiPolygon',
      'coordinates': [
        for (final polygon in coordinates)
          if (polygon is List) _simplifyPolygonCoordinates(polygon),
      ],
    };
  }

  throw StateError('Unsupported geometry type: $type');
}

List<List<List<double>>> _simplifyPolygonCoordinates(List polygon) {
  final rings = <List<List<double>>>[];
  for (final ring in polygon) {
    if (ring is! List) {
      continue;
    }

    final points = <List<double>>[];
    for (final coordinate in ring) {
      if (coordinate is List && coordinate.length >= 2) {
        final longitude = (coordinate[0] as num?)?.toDouble();
        final latitude = (coordinate[1] as num?)?.toDouble();
        if (longitude != null && latitude != null) {
          points.add([longitude, latitude]);
        }
      }
    }

    final simplified = _simplifyRing(points, _simplifyToleranceDegrees);
    if (simplified.length >= 4) {
      rings.add(simplified);
    }
  }

  return rings;
}

List<List<double>> _simplifyRing(List<List<double>> points, double tolerance) {
  if (points.length <= 4) {
    return points;
  }

  final closed =
      points.first[0] == points.last[0] && points.first[1] == points.last[1];
  final openPoints = closed ? points.sublist(0, points.length - 1) : points;
  final simplified = _douglasPeucker(openPoints, tolerance);
  if (simplified.length < 3) {
    return points;
  }

  final first = simplified.first;
  final last = simplified.last;
  if (first[0] != last[0] || first[1] != last[1]) {
    simplified.add([first[0], first[1]]);
  }

  return simplified;
}

List<List<double>> _douglasPeucker(
  List<List<double>> points,
  double tolerance,
) {
  if (points.length <= 2) {
    return [
      for (final point in points) [point[0], point[1]],
    ];
  }

  var maxDistance = 0.0;
  var index = 0;
  final start = points.first;
  final end = points.last;
  for (var i = 1; i < points.length - 1; i++) {
    final distance = _perpendicularDistance(points[i], start, end);
    if (distance > maxDistance) {
      index = i;
      maxDistance = distance;
    }
  }

  if (maxDistance <= tolerance) {
    return [
      [start[0], start[1]],
      [end[0], end[1]],
    ];
  }

  final left = _douglasPeucker(points.sublist(0, index + 1), tolerance);
  final right = _douglasPeucker(points.sublist(index), tolerance);
  return [...left.take(left.length - 1), ...right];
}

double _perpendicularDistance(
  List<double> point,
  List<double> lineStart,
  List<double> lineEnd,
) {
  final dx = lineEnd[0] - lineStart[0];
  final dy = lineEnd[1] - lineStart[1];
  if (dx == 0 && dy == 0) {
    return math.sqrt(
      math.pow(point[0] - lineStart[0], 2) +
          math.pow(point[1] - lineStart[1], 2),
    );
  }

  return ((dy * point[0] -
              dx * point[1] +
              lineEnd[0] * lineStart[1] -
              lineEnd[1] * lineStart[0])
          .abs()) /
      math.sqrt(dx * dx + dy * dy);
}
