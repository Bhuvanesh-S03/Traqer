// --- lib/screens/parent/parent_map.dart ---

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:traqerr/config/assets.dart';

import '../../services/location_service.dart';

class BusData {
  final String busId;
  final String busNumber;
  final String driverName;
  final LatLng location;
  final int timestamp;
  bool isOnline;

  List<LatLng> routePoints;
  List<Map<String, dynamic>> stops;

  BusData({
    required this.busId,
    required this.busNumber,
    required this.driverName,
    required this.location,
    required this.timestamp,
    this.isOnline = false,
    this.routePoints = const [],
    this.stops = const [],
  });
}

class ParentMap extends StatefulWidget {
  final String? assignedBusId;

  const ParentMap({super.key, this.assignedBusId});

  @override
  State<ParentMap> createState() => _ParentMapState();
}

class _ParentMapState extends State<ParentMap> {
  final LocationService _service = LocationService();
  final MapController _mapController = MapController();

  Map<String, BusData> _liveBuses = {};
  String? _selectedBusId;
  List<BusData> _busRoutesData = [];
  bool _initialLoadComplete = false;

  @override
  void initState() {
    super.initState();
    _loadBusRoutesAndStops();
  }

  // 1. Load All Routes and Stops from Firestore (FIXED NESTED LOCATION)
  Future<void> _loadBusRoutesAndStops() async {
    final snap = await FirebaseFirestore.instance.collection('buses').get();
    final List<BusData> routes = [];

    for (var doc in snap.docs) {
      final busId = doc.id;
      final data = doc.data();
      final busNumber = data['busNumber'] ?? 'N/A';

      List<Map<String, dynamic>> stops = [];
      List<LatLng> routePoints = [];

      if (data['stops'] is List) {
        stops = List<Map<String, dynamic>>.from(data['stops']);
        routePoints =
            stops
                // FIX: Check for nested 'location' map
                .where(
                  (s) =>
                      s['location'] != null &&
                      s['location']['lat'] != null &&
                      s['location']['lng'] != null,
                )
                // FIX: Access coordinates inside 'location'
                .map((s) => LatLng(s['location']['lat'], s['location']['lng']))
                .toList();
      }

      routes.add(
        BusData(
          busId: busId,
          busNumber: busNumber,
          driverName: 'Loading...',
          location: MapConstants.defaultMapCenter,
          timestamp: 0,
          routePoints: routePoints,
          stops: stops,
        ),
      );
    }

    setState(() {
      _busRoutesData = routes;
      _selectedBusId =
          widget.assignedBusId ??
          (routes.isNotEmpty ? routes.first.busId : null);
      _initialLoadComplete = true;
    });
  }

  // 2. Logic to Zoom to selected bus/route bounds (LIVE LOCATION PRIORITY)
  void _zoomToBusLocation(String busId, {bool fitToBounds = false}) {
    final liveBus = _liveBuses[busId];

    // PRIORITY 1: Zoom to LIVE BUS LOCATION
    if (liveBus != null && liveBus.isOnline) {
      _mapController.move(liveBus.location, MapConstants.defaultMapZoom);
      return;
    }

    // PRIORITY 2: Fit to STATIC ROUTE BOUNDS (if available and requested)
    if (fitToBounds) {
      final route = _busRoutesData.firstWhere(
        (b) => b.busId == busId,
        orElse:
            () => BusData(
              busId: '',
              busNumber: '',
              driverName: '',
              location: MapConstants.defaultMapCenter,
              timestamp: 0,
            ),
      );

      if (route.routePoints.isNotEmpty) {
        final bounds = LatLngBounds.fromPoints(route.routePoints);
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(50),
            maxZoom: MapConstants.defaultMapZoom + 1,
          ),
        );
        return;
      }
    }

    // PRIORITY 3: Fallback to Default Center
    _mapController.move(
      MapConstants.defaultMapCenter,
      MapConstants.defaultMapZoom,
    );
  }

  // 3. Build Markers based on RTDB data and selection (FIXED NESTED LOCATION)
  List<Marker> _buildMarkers(Map<String, Map<String, dynamic>> busLocations) {
    final markers = <Marker>[];
    final now = DateTime.now().millisecondsSinceEpoch;

    // Process RTDB data and update _liveBuses
    busLocations.forEach((busId, data) {
      final ts = (data['timestamp'] ?? 0) as int;
      final age = now - ts;
      final isOnline = age < MapConstants.offlineThresholdMs;

      final routeData = _busRoutesData.firstWhere(
        (b) => b.busId == busId,
        orElse:
            () => BusData(
              busId: busId,
              busNumber: data['busNumber'] ?? 'Unknown',
              driverName: data['driverName'] ?? 'Unknown',
              location: MapConstants.defaultMapCenter,
              timestamp: 0,
            ),
      );

      _liveBuses[busId] = BusData(
        busId: busId,
        busNumber: data['busNumber'],
        driverName: data['driverName'],
        location: LatLng(data['lat'], data['lng']),
        timestamp: ts,
        isOnline: isOnline,
        routePoints: routeData.routePoints,
        stops: routeData.stops,
      );
    });

    // Add Bus Markers (Differentiating assigned, other, and offline)
    _liveBuses.forEach((busId, bus) {
      // Only draw the selected bus marker and any other online buses for context
      if (!bus.isOnline && busId != _selectedBusId) {
        return;
      }

      Color color;
      String iconText = AppIcons.onlineBusIcon;

      if (!bus.isOnline) {
        color = AppColors.offlineBusColor; // Red
        iconText = AppIcons.offlineBusIcon;
      } else if (busId == widget.assignedBusId) {
        color = AppColors.assignedBusColor; // Green (Assigned)
      } else {
        color = AppColors.otherBusColor; // Blue (Other Active)
      }

      markers.add(
        Marker(
          width: MapConstants.markerSize,
          height: MapConstants.markerSize,
          point: bus.location,
          child: GestureDetector(
            onTap: () => _showBusInfo(bus),
            child: Text(
              iconText,
              style: TextStyle(
                fontSize: MapConstants.busIconFontSize,
                color: color,
              ),
            ),
          ),
        ),
      );
    });

    // Add Bus Stop Markers (Only for the selected route)
    final selectedBusRouteData = _busRoutesData.firstWhere(
      (b) => b.busId == _selectedBusId,
      orElse:
          () => BusData(
            busId: '',
            busNumber: '',
            driverName: '',
            location: MapConstants.defaultMapCenter,
            timestamp: 0,
          ),
    );

    for (final stop in selectedBusRouteData.stops) {
      // FIX: Access coordinates inside 'location' map
      final double? lat = stop['location']?['lat'] as double?;
      final double? lng = stop['location']?['lng'] as double?;

      if (lat != null && lng != null) {
        markers.add(
          Marker(
            width: MapConstants.markerSize * 0.8,
            height: MapConstants.markerSize * 0.8,
            point: LatLng(lat, lng),
            child: Text(
              AppIcons.busStopIcon,
              style: TextStyle(
                fontSize: MapConstants.stopIconFontSize,
                // FIX: Dark color for visibility
                color: Colors.grey.shade900,
              ),
            ),
          ),
        );
      }
    }

    return markers;
  }

  // 4. Show Info Window on Marker Tap (remains the same)
  void _showBusInfo(BusData bus) {
    final status = bus.isOnline ? 'Online' : 'Offline';
    final statusColor =
        bus.isOnline ? Colors.green.shade700 : Colors.red.shade700;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (context) => Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bus: ${bus.busNumber}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Divider(),
                _buildInfoRow('Driver', bus.driverName, Icons.person),
                _buildInfoRow('Status', status, Icons.wifi, statusColor),
                _buildInfoRow(
                  'Last Update',
                  '${DateTime.fromMillisecondsSinceEpoch(bus.timestamp).toLocal().toString().split('.').first}',
                  Icons.access_time,
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildInfoRow(
    String title,
    String value,
    IconData icon, [
    Color? color,
  ]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: color ?? Colors.grey.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$title:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  // 5. Build Map Widget
  @override
  Widget build(BuildContext context) {
    final selectedBusRoute = _busRoutesData.firstWhere(
      (b) => b.busId == _selectedBusId,
      orElse:
          () => BusData(
            busId: '',
            busNumber: '',
            driverName: '',
            location: MapConstants.defaultMapCenter,
            timestamp: 0,
          ),
    );

    // Guard against empty point list before creating the polyline
    final List<Polyline> routePolylines =
        (selectedBusRoute.routePoints.isNotEmpty)
            ? [
              Polyline(
                points: selectedBusRoute.routePoints,
                strokeWidth: 5.0,
                color: AppColors.assignedBusColor.withOpacity(0.6),
                borderStrokeWidth: 1.0,
                borderColor: Colors.black.withOpacity(0.3),
              ),
            ]
            : [];

    return Column(
      children: [
        // Dropdown Selector
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: DropdownButtonFormField<String>(
            decoration: InputDecoration(
              labelText: 'Select Bus Route to Track',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              prefixIcon: const Icon(Icons.route),
            ),
            value: _selectedBusId,
            items:
                _busRoutesData.map((bus) {
                  final isAssigned = bus.busId == widget.assignedBusId;
                  return DropdownMenuItem<String>(
                    value: bus.busId,
                    child: Text(
                      '${bus.busNumber} ${isAssigned ? '(Your Assigned Bus)' : ''}',
                    ),
                  );
                }).toList(),
            onChanged: (String? newBusId) {
              if (newBusId != null) {
                setState(() => _selectedBusId = newBusId);
                // Call zoom logic with bounds enabled for selection change
                _zoomToBusLocation(newBusId, fitToBounds: true);
              }
            },
          ),
        ),
        // Map View
        Expanded(
          child: StreamBuilder<Map<String, Map<String, dynamic>>>(
            stream: _service.getAllBusLocations(),
            builder: (context, snap) {
              final markers = _buildMarkers(snap.data ?? {});

              // CRITICAL FIX: Zoom to the assigned bus's live location if available on initial load
              if (_initialLoadComplete &&
                  snap.hasData &&
                  _selectedBusId != null) {
                final assignedBusIsOnline =
                    _liveBuses[_selectedBusId]?.isOnline == true;

                // If the assigned bus is online, zoom to its live location
                if (assignedBusIsOnline) {
                  _zoomToBusLocation(_selectedBusId!, fitToBounds: false);
                }
              }

              return FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: MapConstants.defaultMapCenter,
                  initialZoom: MapConstants.defaultMapZoom,
                  maxZoom: 18,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                    subdomains: const ['a', 'b', 'c'],
                  ),
                  PolylineLayer(polylines: routePolylines),
                  MarkerLayer(markers: markers),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
