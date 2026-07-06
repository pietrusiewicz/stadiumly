import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

void main() {
  runApp(const StadiumlyApp());
}

class StadiumlyApp extends StatelessWidget {
  const StadiumlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stadiumly',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF167A4A)),
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
    this.visited = false,
  });

  final int id;
  final String name;
  final LatLng position;
  final bool visited;

  Waypoint copyWith({String? name, bool? visited}) {
    return Waypoint(
      id: id,
      name: name ?? this.name,
      position: position,
      visited: visited ?? this.visited,
    );
  }
}

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
      name: 'Start: Warsaw center',
      position: _initialCenter,
    ),
  ];

  int _nextWaypointId = 2;

  int get _visitedCount =>
      _waypoints.where((waypoint) => waypoint.visited).length;

  void _addWaypoint(TapPosition _, LatLng position) {
    setState(() {
      final id = _nextWaypointId++;
      _waypoints.add(
        Waypoint(id: id, name: 'Waypoint $id', position: position),
      );
    });
  }

  void _toggleVisited(Waypoint waypoint) {
    setState(() {
      final index = _waypoints.indexWhere((item) => item.id == waypoint.id);
      if (index == -1) {
        return;
      }

      _waypoints[index] = waypoint.copyWith(visited: !waypoint.visited);
    });
  }

  void _deleteWaypoint(Waypoint waypoint) {
    setState(() {
      _waypoints.removeWhere((item) => item.id == waypoint.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stadiumly'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text('Visited $_visitedCount/${_waypoints.length}'),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: 13,
              onTap: _addWaypoint,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.stadiumly',
              ),
              MarkerLayer(
                markers: [
                  for (final waypoint in _waypoints)
                    Marker(
                      point: waypoint.position,
                      width: 44,
                      height: 44,
                      child: _WaypointMarker(
                        waypoint: waypoint,
                        onPressed: () => _toggleVisited(waypoint),
                      ),
                    ),
                ],
              ),
            ],
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              minimum: const EdgeInsets.all(12),
              child: _WaypointPanel(
                waypoints: _waypoints,
                onToggleVisited: _toggleVisited,
                onDelete: _deleteWaypoint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaypointMarker extends StatelessWidget {
  const _WaypointMarker({required this.waypoint, required this.onPressed});

  final Waypoint waypoint;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = waypoint.visited ? Colors.green : Colors.redAccent;

    return Tooltip(
      message: waypoint.name,
      child: IconButton.filled(
        onPressed: onPressed,
        style: IconButton.styleFrom(backgroundColor: color),
        icon: Icon(
          waypoint.visited ? Icons.check : Icons.place,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _WaypointPanel extends StatelessWidget {
  const _WaypointPanel({
    required this.waypoints,
    required this.onToggleVisited,
    required this.onDelete,
  });

  final List<Waypoint> waypoints;
  final ValueChanged<Waypoint> onToggleVisited;
  final ValueChanged<Waypoint> onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 260),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              dense: true,
              title: Text('Waypoints'),
              subtitle: Text(
                'Tap the map to add a point. Tap a marker to visit.',
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: waypoints.isEmpty
                  ? const Center(child: Text('No waypoints yet'))
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: waypoints.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final waypoint = waypoints[index];

                        return CheckboxListTile(
                          dense: true,
                          value: waypoint.visited,
                          onChanged: (_) => onToggleVisited(waypoint),
                          title: Text(waypoint.name),
                          subtitle: Text(
                            '${waypoint.position.latitude.toStringAsFixed(5)}, '
                            '${waypoint.position.longitude.toStringAsFixed(5)}',
                          ),
                          secondary: IconButton(
                            tooltip: 'Delete waypoint',
                            onPressed: () => onDelete(waypoint),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
