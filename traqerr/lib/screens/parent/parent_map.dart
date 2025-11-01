// --- lib/screens/parent/parent_map.dart ---
// FINAL FIXES: Smooth movement, 3s data stream, simplified UI, dynamic stops, ETA notification.
// CRITICAL FIX: Resolved layout overflow issues in the bus information modal.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:traqerr/config/assets.dart';
import 'dart:async';
import 'dart:math';
import '../../services/location_service.dart';
import 'package:geolocator/geolocator.dart'; // Needed for distance calculation

// Helper function for interpolation
LatLng interpolate(LatLng start, LatLng end, double fraction) {
  final lat = start.latitude + (end.latitude - start.latitude) * fraction;
  final lng = start.longitude + (end.longitude - start.longitude) * fraction;
  return LatLng(lat, lng);
}

class BusData {
  final String busId;
  final String busNumber;
  final String driverName;
  final LatLng location;
  final int timestamp;
  final double speed;
  final double heading;
  bool isOnline;
  List<LatLng> routePoints;
  List<Map<String, dynamic>> stops;

  BusData({
    required this.busId,
    required this.busNumber,
    required this.driverName,
    required this.location,
    required this.timestamp,
    this.speed = 0.0,
    this.heading = 0.0,
    this.isOnline = false,
    this.routePoints = const [],
    this.stops = const [],
  });

  BusData copyWith({
    LatLng? location,
    int? timestamp,
    bool? isOnline,
    double? speed,
    double? heading,
    List<Map<String, dynamic>>? stops,
  }) {
    return BusData(
      busId: busId,
      busNumber: busNumber,
      driverName: driverName,
      location: location ?? this.location,
      timestamp: timestamp ?? this.timestamp,
      speed: speed ?? this.speed,
      heading: heading ?? this.heading,
      isOnline: isOnline ?? this.isOnline,
      routePoints: routePoints,
      stops: stops ?? this.stops,
    );
  }
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

  Map<String, LatLng> _interpolatedLocations = {};
  Map<String, LatLng> _targetLocations = {};
  Map<String, double> _currentHeadings = {};
  Map<String, BusData> _busCache = {};

  String? _selectedBusId;
  List<BusData> _busRoutesData = [];
  bool _initialLoadComplete = false;
  bool _autoFollow = true;

  bool _hasNotifiedForBus = false;

  Timer? _staleCheckTimer;
  Timer? _interpolationTimer;

  static const int _interpolationStepMs = 50;
  static const double _interpolationFactor = 0.05;
  static const double _movementThresholdMps = 0.5;
  static const double _stopVisibilityRangeMeters =
      500.0; // Show stops within 500m

  final Color primaryColor = const Color(0xFF1E88E5); // Blue
  final Color secondaryColor = const Color(0xFF00C896); // Teal/Green

  @override
  void initState() {
    super.initState();
    _loadBusRoutesAndStops();
    _startStaleDataCheck();
    _startInterpolationTimer();
  }

  @override
  void dispose() {
    _staleCheckTimer?.cancel();
    _interpolationTimer?.cancel();
    super.dispose();
  }

  // CRITICAL FIX: Interpolation timer now includes proximity check
  void _startInterpolationTimer() {
    _interpolationTimer = Timer.periodic(
      const Duration(milliseconds: _interpolationStepMs),
      (timer) {
        if (!mounted) return;

        bool needsUpdate = false;
        final newInterpolatedLocations = Map<String, LatLng>.from(
          _interpolatedLocations,
        );
        final newCurrentHeadings = Map<String, double>.from(_currentHeadings);

        _busCache.forEach((busId, bus) {
          final current = _interpolatedLocations[busId];
          final target = _targetLocations[busId];

          if (current != null && target != null && current != target) {
            // Move the marker closer to the target using a fixed factor (0.05)
            final nextPosition = interpolate(
              current,
              target,
              _interpolationFactor,
            );
            newInterpolatedLocations[busId] = nextPosition;
            needsUpdate = true;
          } else if (current == null && target != null) {
            // Initialize marker position if new
            newInterpolatedLocations[busId] = target;
            needsUpdate = true;
          }

          // Update heading for rotation (only when moving)
          final isMoving = bus.speed > _movementThresholdMps;
          if (isMoving && bus.heading > 0) {
            double currentHeading = _currentHeadings[busId] ?? 0.0;
            double targetHeading = bus.heading;

            double diff = targetHeading - currentHeading;
            if (diff > 180) diff -= 360;
            if (diff < -180) diff += 360;

            // Move 10% of the difference per step
            newCurrentHeadings[busId] = (currentHeading + diff * 0.1) % 360;
            needsUpdate = true;
          }
        });

        if (needsUpdate) {
          setState(() {
            _interpolatedLocations = newInterpolatedLocations;
            _currentHeadings = newCurrentHeadings;
            _handleAutoFollow();
          });

          // CRITICAL: Run proximity check after map update
          _checkBusStopProximityAndNotify();
        }
      },
    );
  }

  void _startStaleDataCheck() {
    _staleCheckTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      bool needsUpdate = false;

      final updatedBusCache = Map<String, BusData>.from(_busCache);

      updatedBusCache.forEach((busId, bus) {
        final age = now - bus.timestamp;
        const int staleThreshold = 30000;
        final isOnline = age < staleThreshold;

        if (bus.isOnline != isOnline) {
          updatedBusCache[busId] = bus.copyWith(isOnline: isOnline);
          needsUpdate = true;
        }
      });

      if (needsUpdate && mounted) {
        setState(() {
          _busCache = updatedBusCache;
        });
      }
    });
  }

  // MANUAL RELOAD & RECENTER FUNCTION
  Future<void> _handleReloadAndRecenter() async {
    // 1. Visually indicate reload
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
              const SizedBox(width: 12),
              Text(
                'Reloading bus data and recentering map...',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: primaryColor,
        ),
      );
    }

    // 2. Reload static bus route data (Firestore fetch)
    await _loadBusRoutesAndStops();

    // 3. Recenter map
    if (_selectedBusId != null) {
      _zoomToBusLocation(_selectedBusId!, animated: true);
    }
  }

  Future<void> _loadBusRoutesAndStops() async {
    if (mounted) {
      setState(() => _initialLoadComplete = false);
    }
    try {
      final snap = await FirebaseFirestore.instance.collection('buses').get();
      final List<BusData> routes = [];

      for (var doc in snap.docs) {
        final busId = doc.id;
        final data = doc.data();
        final busNumber = data['busNumber'] ?? 'N/A';
        final driverName = data['driverName'] ?? 'Waiting...';

        List<Map<String, dynamic>> stops = [];

        if (data['stops'] is List) {
          stops = List<Map<String, dynamic>>.from(data['stops']);
        }

        routes.add(
          BusData(
            busId: busId,
            busNumber: busNumber,
            driverName: driverName,
            location: MapConstants.defaultMapCenter,
            timestamp: 0,
            routePoints: [],
            stops: stops,
          ),
        );
      }

      if (mounted) {
        setState(() {
          _busRoutesData = routes;
          _selectedBusId =
              widget.assignedBusId ??
              (routes.isNotEmpty ? routes.first.busId : null);
          _initialLoadComplete = true;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading bus routes: $e');
      if (mounted) {
        setState(() => _initialLoadComplete = true);
      }
    }
  }

  void _handleAutoFollow() {
    if (!_autoFollow || _selectedBusId == null) return;

    final selectedBus = _busCache[_selectedBusId];
    final interpolatedPosition = _interpolatedLocations[_selectedBusId];

    if (selectedBus != null &&
        selectedBus.isOnline &&
        interpolatedPosition != null) {
      _mapController.move(interpolatedPosition, _mapController.camera.zoom);
    }
  }

  void _zoomToBusLocation(String busId, {bool animated = true}) {
    final liveBus = _busCache[busId];
    final locationToFocus = liveBus?.location;

    if (locationToFocus != null) {
      _mapController.move(locationToFocus, 16.0);
    }
  }

  List<Marker> _buildBusMarkers(
    Map<String, Map<String, dynamic>> busLocations,
  ) {
    final markers = <Marker>[];
    final now = DateTime.now().millisecondsSinceEpoch;

    // 1. Process new data (updates cache and interpolation targets)
    busLocations.forEach((busId, data) {
      final ts = (data['timestamp'] ?? 0) as int;
      final isOnline = (now - ts) < 30000;
      final newLocation = LatLng(
        (data['lat'] as num?)?.toDouble() ?? 0.0,
        (data['lng'] as num?)?.toDouble() ?? 0.0,
      );
      final speed = (data['speed'] as num?)?.toDouble() ?? 0.0;
      final heading = (data['heading'] as num?)?.toDouble() ?? 0.0;

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

      final busData = BusData(
        busId: busId,
        busNumber: data['busNumber'] ?? 'Bus',
        driverName: data['driverName'] ?? 'Driver',
        location: newLocation,
        timestamp: ts,
        speed: speed,
        heading: heading,
        isOnline: isOnline,
        routePoints: routeData.routePoints,
        stops: routeData.stops,
      );

      _busCache[busId] = busData;
      _targetLocations[busId] = newLocation;

      if (!_interpolatedLocations.containsKey(busId)) {
        _interpolatedLocations[busId] = newLocation;
      }
      if (!_currentHeadings.containsKey(busId)) {
        _currentHeadings[busId] = heading;
      }
    });

    // 2. Build Bus Markers (live/last-known)
    _busCache.forEach((busId, bus) {
      final interpolatedLocation = _interpolatedLocations[busId];
      if (interpolatedLocation == null) return;

      Color color;
      double size = MapConstants.markerSize;
      final isMoving = bus.isOnline && bus.speed > _movementThresholdMps;
      final heading = _currentHeadings[busId] ?? 0.0;

      if (!bus.isOnline) {
        // Red for offline bus (last known location)
        color = Colors.red.shade600;
        size = MapConstants.markerSize * 1.2;
      } else {
        // Green/Custom for online bus
        color = secondaryColor;
        size = MapConstants.markerSize * 1.4;
      }

      markers.add(
        Marker(
          width: size * 1.2,
          height: size * 1.2,
          point: interpolatedLocation,
          child: GestureDetector(
            onTap: () => _showBusInfo(bus),
            child: Transform.rotate(
              angle: (heading * pi) / 180,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.6),
                      blurRadius: 15,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    // Use a directional icon when moving, or a static one when stopped/offline
                    isMoving
                        ? Icons.arrow_circle_up
                        : Icons.directions_bus_filled,
                    size: size * 0.7,
                    color: color,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
    return markers;
  }

  // CRITICAL FIX: Bus stops are visible ONLY when a bus is near them.
  List<Marker> _buildBusStopMarkers() {
    if (_selectedBusId == null) return [];

    final selectedBusRouteData = _busRoutesData.firstWhere(
      (b) => b.busId == _selectedBusId,
      orElse:
          () => BusData(
            busId: '',
            busNumber: '',
            driverName: '',
            location: MapConstants.defaultMapCenter,
            timestamp: 0,
            stops: [],
          ),
    );

    final currentBusLocation = _interpolatedLocations[_selectedBusId];
    if (currentBusLocation == null) return [];

    final markers = <Marker>[];

    for (final stop in selectedBusRouteData.stops) {
      final double? lat = stop['location']?['lat'] as double?;
      final double? lng = stop['location']?['lng'] as double?;
      final String stopName = stop['name'] ?? 'Stop';

      if (lat != null && lng != null) {
        final stopLocation = LatLng(lat, lng);

        // Check distance to the current bus location
        final distanceToStop = Geolocator.distanceBetween(
          currentBusLocation.latitude,
          currentBusLocation.longitude,
          stopLocation.latitude,
          stopLocation.longitude,
        );

        // Only show the stop marker if the bus is within the visibility range (500m)
        if (distanceToStop < _stopVisibilityRangeMeters) {
          markers.add(
            Marker(
              width: 40,
              height: 40,
              point: stopLocation,
              child: GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('🛑 $stopName'),
                      duration: const Duration(seconds: 2),
                      backgroundColor: primaryColor,
                    ),
                  );
                },
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: Colors.amber.shade700, width: 3),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.location_on,
                      size: 20,
                      color: Colors.amber.shade700,
                    ),
                  ),
                ),
              ),
            ),
          );
        }
      }
    }
    return markers;
  }

  void _showBusInfo(BusData bus) {
    final status = bus.isOnline ? 'Online' : 'Offline';
    final statusColor =
        bus.isOnline ? Colors.green.shade700 : Colors.red.shade700;
    final lastUpdate =
        DateTime.fromMillisecondsSinceEpoch(bus.timestamp).toLocal();
    final timeDiff = DateTime.now().difference(lastUpdate);
    final timeAgo =
        timeDiff.inMinutes > 0
            ? '${timeDiff.inMinutes}m ${timeDiff.inSeconds % 60}s ago'
            : '${timeDiff.inSeconds}s ago';

    final isMoving = bus.isOnline && bus.speed > _movementThresholdMps;
    final movementStatus = isMoving ? 'Moving' : 'Stopped';
    final movementColor = isMoving ? secondaryColor : Colors.orange.shade600;
    final movementIcon =
        isMoving ? Icons.trending_up : Icons.pause_circle_filled;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
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
                Row(
                  children: [
                    // FIX: Wrap bus number text in Expanded to prevent horizontal overflow
                    Expanded(
                      child: Text(
                        '🚌 ${bus.busNumber}',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8), // Small gap between text and chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusColor, width: 2),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 30, thickness: 2),

                _buildInfoRow(
                  'Movement',
                  movementStatus,
                  movementIcon,
                  movementColor,
                ),
                _buildInfoRow(
                  'Driver',
                  bus.driverName,
                  Icons.person,
                  Colors.grey,
                ),
                _buildInfoRow(
                  'Speed',
                  '${(bus.speed * 3.6).toStringAsFixed(1)} km/h',
                  Icons.speed,
                  Colors.grey,
                ),
                _buildInfoRow(
                  'Last Update',
                  timeAgo,
                  Icons.access_time,
                  Colors.grey,
                ),
                _buildInfoRow(
                  'Heading',
                  '${bus.heading.toStringAsFixed(1)}°',
                  Icons.explore,
                  Colors.grey,
                ),
              ],
            ),
          ),
    );
  }

  // FIX: Reworked _buildInfoRow to use Expanded for the value text, guaranteeing fit.
  Widget _buildInfoRow(
    String title,
    String value,
    IconData icon,
    Color iconColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 12),
          Text(
            '$title:',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
              fontSize: 15,
            ),
          ),
          const SizedBox(width: 12),
          // CRITICAL: Expanded ensures this text field takes only available space.
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ... (rest of the file remains unchanged)

  LatLng? _getAssignedStudentStop() {
    if (widget.assignedBusId == null) return null;

    final assignedRoute = _busRoutesData.firstWhere(
      (b) => b.busId == widget.assignedBusId,
      orElse:
          () => BusData(
            busId: '',
            busNumber: '',
            driverName: '',
            location: MapConstants.defaultMapCenter,
            timestamp: 0,
            stops: [],
          ),
    );

    if (assignedRoute.stops.isNotEmpty) {
      final stop = assignedRoute.stops.first;
      final lat = stop['location']?['lat'] as double?;
      final lng = stop['location']?['lng'] as double?;
      if (lat != null && lng != null) {
        return LatLng(lat, lng);
      }
    }
    return null;
  }

  // NEW: Function to check proximity and notify
  void _checkBusStopProximityAndNotify() {
    if (widget.assignedBusId == null) return;

    final assignedBus = _busCache[widget.assignedBusId];
    final assignedStop = _getAssignedStudentStop();

    if (assignedBus == null || assignedStop == null || !assignedBus.isOnline) {
      _hasNotifiedForBus = false;
      return;
    }

    final currentBusLocation = _interpolatedLocations[widget.assignedBusId];
    if (currentBusLocation == null) return;

    final distanceToStopMeters = Geolocator.distanceBetween(
      currentBusLocation.latitude,
      currentBusLocation.longitude,
      assignedStop.latitude,
      assignedStop.longitude,
    );

    final speedMps = max(assignedBus.speed, 1.5);
    final etaMinutes = (distanceToStopMeters / speedMps) / 60;

    const double notificationWindowMinutes = 5.0;

    if (etaMinutes <= notificationWindowMinutes && !_hasNotifiedForBus) {
      _hasNotifiedForBus = true;
      debugPrint(
        '*** NOTIFICATION TRIGGERED: ETA is ${etaMinutes.toStringAsFixed(1)} min ***',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '🔔 Your bus (${assignedBus.busNumber}) will reach your stop in ${etaMinutes.toStringAsFixed(1)} minutes!',
          ),
          duration: const Duration(seconds: 10),
          backgroundColor: secondaryColor,
        ),
      );
    } else if (etaMinutes > 10.0) {
      _hasNotifiedForBus = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Polyline> routePolylines = [];

    return Scaffold(
      body: Column(
        children: [
          // GRAND AND MINIMALIST CONTROL PANEL (BUS SELECTION ONLY)
          Container(
            padding: const EdgeInsets.fromLTRB(18.0, 18.0, 18.0, 10.0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: SafeArea(
              bottom: false,
              child: DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: 'Select Bus to Track',
                  labelStyle: const TextStyle(fontWeight: FontWeight.w600),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: primaryColor, width: 2),
                  ),
                  prefixIcon: Icon(Icons.directions_bus, color: primaryColor),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                value: _selectedBusId,
                items:
                    _busRoutesData.map((bus) {
                      final isAssigned = bus.busId == widget.assignedBusId;
                      final isOnline = _busCache[bus.busId]?.isOnline ?? false;
                      return DropdownMenuItem<String>(
                        value: bus.busId,
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isOnline ? secondaryColor : Colors.red,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '${bus.busNumber} ${isAssigned ? ' (My Bus)' : ''}',
                              style: TextStyle(
                                fontWeight:
                                    isAssigned
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                color:
                                    isOnline
                                        ? Colors.black
                                        : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                onChanged: (String? newBusId) {
                  if (newBusId != null) {
                    setState(() {
                      _selectedBusId = newBusId;
                      _autoFollow =
                          true; // Start following the newly selected bus
                    });
                    _zoomToBusLocation(newBusId, animated: true);
                  }
                },
              ),
            ),
          ),

          // MAP
          Expanded(
            child: StreamBuilder<Map<String, Map<String, dynamic>>>(
              stream: _service.getAllBusLocations(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !_initialLoadComplete) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snap.hasError) {
                  return _buildErrorState(snap.error.toString());
                }

                final busData = snap.data ?? {};
                final busMarkers = _buildBusMarkers(busData);
                final busStopMarkers =
                    _buildBusStopMarkers(); // Conditional visibility
                final allMarkers = [...busMarkers, ...busStopMarkers];

                if (allMarkers.isEmpty &&
                    _initialLoadComplete &&
                    _busRoutesData.isEmpty) {
                  return _buildNoBusState();
                }

                return FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: MapConstants.defaultMapCenter,
                    initialZoom: MapConstants.defaultMapZoom,
                    maxZoom: 19,
                    minZoom: 10,
                    // Disable auto-follow on user drag
                    onMapEvent: (event) {
                      if (event is MapEventMove &&
                          event.source == MapEventSource.dragStart) {
                        setState(() => _autoFollow = false);
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                      subdomains: const ['a', 'b', 'c'],
                      userAgentPackageName: 'com.example.traqerr',
                    ),
                    PolylineLayer(polylines: routePolylines),
                    MarkerLayer(markers: allMarkers),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      // FLOATING ACTION BUTTONS (RELOAD + RECENTER)
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // 1. Follow/Location Toggle Button
          FloatingActionButton(
            heroTag: 'followBtn',
            backgroundColor: _autoFollow ? primaryColor : Colors.grey.shade600,
            foregroundColor: Colors.white,
            onPressed: () {
              setState(() => _autoFollow = !_autoFollow);
              if (_autoFollow && _selectedBusId != null) {
                _zoomToBusLocation(_selectedBusId!, animated: true);
              }
            },
            child: Icon(
              _autoFollow ? Icons.my_location : Icons.location_disabled,
            ),
          ),
          const SizedBox(height: 10),
          // 2. Reload & Recenter Button
          FloatingActionButton(
            heroTag: 'reloadCenterBtn',
            backgroundColor: secondaryColor,
            foregroundColor: Colors.white,
            onPressed: _handleReloadAndRecenter,
            child: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 70, color: Colors.red),
          const SizedBox(height: 20),
          Text(
            'Connection Error',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.red.shade700,
            ),
          ),
          const SizedBox(height: 10),
          Text(error),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _handleReloadAndRecenter,
            icon: const Icon(Icons.refresh),
            label: const Text('Reload & Recenter'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade500,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoBusState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bus_alert, size: 70, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No Active Buses',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Waiting for drivers to start tracking.',
            style: TextStyle(color: Colors.grey.shade500),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _handleReloadAndRecenter,
            icon: const Icon(Icons.refresh),
            label: const Text('Reload & Recenter'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo.shade500,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
