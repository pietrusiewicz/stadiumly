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
    this.visited = false,
  });

  final int id;
  final String name;
  final LatLng position;
  final String category;
  final bool visited;

  Waypoint copyWith({String? name, String? category, bool? visited}) {
    return Waypoint(
      id: id,
      name: name ?? this.name,
      position: position,
      category: category ?? this.category,
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
      name: 'National Stadium',
      category: 'Match day',
      position: LatLng(52.2394, 21.0458),
      visited: true,
    ),
    const Waypoint(
      id: 2,
      name: 'Old Town meeting point',
      category: 'Walk',
      position: LatLng(52.2499, 21.0122),
    ),
    const Waypoint(
      id: 3,
      name: 'Riverside checkpoint',
      category: 'Route',
      position: LatLng(52.2356, 21.0314),
    ),
  ];

  int _nextWaypointId = 4;

  int get _visitedCount =>
      _waypoints.where((waypoint) => waypoint.visited).length;

  double get _progress =>
      _waypoints.isEmpty ? 0 : _visitedCount / _waypoints.length;

  void _addWaypoint(TapPosition _, LatLng position) {
    setState(() {
      final id = _nextWaypointId++;
      _waypoints.add(
        Waypoint(
          id: id,
          name: 'Waypoint $id',
          category: 'New stop',
          position: position,
        ),
      );
    });
  }

  void _addCenterWaypoint() {
    _addWaypoint(TapPosition(Offset.zero, Offset.zero), _initialCenter);
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
                userAgentPackageName: 'com.pietrusiewicz.stadiumly',
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
                        onPressed: () => _toggleVisited(waypoint),
                      ),
                    ),
                ],
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _TripSummary(
                visitedCount: _visitedCount,
                totalCount: _waypoints.length,
                progress: _progress,
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _WaypointPanel(
                waypoints: _waypoints,
                onAddWaypoint: _addCenterWaypoint,
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

class _TripSummary extends StatelessWidget {
  const _TripSummary({
    required this.visitedCount,
    required this.totalCount,
    required this.progress,
  });

  final int visitedCount;
  final int totalCount;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

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
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.route, color: colors.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Stadiumly',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text('Plan, visit, remember.'),
                    ],
                  ),
                ),
                Text(
                  '$visitedCount/$totalCount',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: progress,
                backgroundColor: colors.surfaceContainerHighest,
              ),
            ),
          ],
        ),
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
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(5),
          child: CircleAvatar(
            backgroundColor: color,
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

class _WaypointPanel extends StatelessWidget {
  const _WaypointPanel({
    required this.waypoints,
    required this.onAddWaypoint,
    required this.onToggleVisited,
    required this.onDelete,
  });

  final List<Waypoint> waypoints;
  final VoidCallback onAddWaypoint;
  final ValueChanged<Waypoint> onToggleVisited;
  final ValueChanged<Waypoint> onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

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
                    '${waypoints.length} stops',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: onAddWaypoint,
                    icon: const Icon(Icons.add_location_alt, size: 18),
                    label: const Text('Add'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: waypoints.isEmpty
                  ? const Center(child: Text('No waypoints yet'))
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: waypoints.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final waypoint = waypoints[index];

                        return _WaypointTile(
                          waypoint: waypoint,
                          onToggleVisited: () => onToggleVisited(waypoint),
                          onDelete: () => onDelete(waypoint),
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

class _WaypointTile extends StatelessWidget {
  const _WaypointTile({
    required this.waypoint,
    required this.onToggleVisited,
    required this.onDelete,
  });

  final Waypoint waypoint;
  final VoidCallback onToggleVisited;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      leading: Checkbox(
        value: waypoint.visited,
        onChanged: (_) => onToggleVisited(),
      ),
      title: Text(
        waypoint.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          decoration: waypoint.visited ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(
        '${waypoint.category} - '
        '${waypoint.position.latitude.toStringAsFixed(4)}, '
        '${waypoint.position.longitude.toStringAsFixed(4)}',
      ),
      trailing: IconButton(
        tooltip: 'Delete waypoint',
        onPressed: onDelete,
        color: colors.onSurfaceVariant,
        icon: const Icon(Icons.delete_outline),
      ),
    );
  }
}
