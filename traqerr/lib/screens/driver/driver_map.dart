// --- lib/screens/driver/driver_map.dart ---
// OPTIMIZED: Low battery + smooth map updates
// UI/UX: Professional, Minimalist Control Panel

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:traqerr/config/assets.dart';
import '../../services/location_service.dart';

class DriverDetails {
  final String busId;
  final String busNumber;
  final String driverName;
  final List<LatLng> routePoints;
  final List<Map<String, dynamic>> stops;

  DriverDetails({
    required this.busId,
    required this.busNumber,
    required this.driverName,
    this.routePoints = const [],
    this.stops = const [],
  });
}

class DriverMapTab extends StatefulWidget {
  const DriverMapTab({super.key});

  @override
  State<DriverMapTab> createState() => _DriverMapTabState();
}

class _DriverMapTabState extends State<DriverMapTab> {
  final LocationService _locationService = LocationService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final MapController _mapController = MapController();

  bool _isTracking = false;
  String _statusMessage = 'Ready to Start';
  DriverDetails? _driverDetails;
  LatLng _currentLocation = MapConstants.defaultMapCenter;

  // Performance metrics
  double _currentSpeed = 0.0;
  double _totalDistance = 0.0;
  int _updateCount = 0;
  DateTime? _tripStartTime;

  // Changed to a more professional primary color
  final Color primaryColor = const Color(0xFF00C896); // Teal/Green
  final Color darkPrimaryColor = const Color(
    0xFF008060,
  ); // Darker Teal/Green for contrast
  final Color accentColor = const Color(0xFF1E88E5); // Blue

  @override
  void initState() {
    super.initState();
    _fetchDriverDetails();
  }

  Future<void> _fetchDriverDetails() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    if (mounted) {
      setState(() {
        _statusMessage = 'Refreshing data...';
      });
    }

    try {
      final doc =
          await FirebaseFirestore.instance.collection('drivers').doc(uid).get();

      if (doc.exists) {
        final data = doc.data();
        final busId = data?['assignedBus'];
        final driverName = data?['name'] ?? 'Driver';

        String busNumber = 'N/A';
        List<LatLng> routePoints = [];
        List<Map<String, dynamic>> stops = [];

        if (busId != null && busId.isNotEmpty) {
          final busDoc =
              await FirebaseFirestore.instance
                  .collection('buses')
                  .doc(busId)
                  .get();
          final busData = busDoc.data();

          busNumber = busData?['busNumber'] ?? 'N/A';

          if (busData?['stops'] is List) {
            stops = List<Map<String, dynamic>>.from(busData!['stops']);
            routePoints =
                stops
                    .where(
                      (s) =>
                          s['location'] != null &&
                          s['location']['lat'] != null &&
                          s['location']['lng'] != null,
                    )
                    .map(
                      (s) => LatLng(s['location']['lat'], s['location']['lng']),
                    )
                    .toList();
          }
        }

        if (mounted) {
          setState(() {
            _driverDetails = DriverDetails(
              busId: busId ?? '',
              busNumber: busNumber,
              driverName: driverName,
              routePoints: routePoints,
              stops: stops,
            );
            _statusMessage =
                busId != null && busId.isNotEmpty
                    ? 'Ready to track Bus: $busNumber'
                    : '⚠️ No Bus Assigned';

            if (routePoints.isNotEmpty) {
              _currentLocation = routePoints.first;
              final bounds = LatLngBounds.fromPoints(routePoints);
              _mapController.fitCamera(
                CameraFit.bounds(
                  bounds: bounds,
                  padding: const EdgeInsets.all(50),
                ),
              );
            } else {
              _mapController.move(
                _currentLocation,
                MapConstants.defaultMapZoom,
              );
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching driver details: $e');
      if (mounted) {
        setState(() => _statusMessage = 'Error loading data');
      }
    }
  }

  Future<void> _toggleTracking() async {
    final busId = _driverDetails?.busId;
    if (busId == null || busId.isEmpty) {
      setState(() => _statusMessage = '❌ Cannot start: No Bus ID');
      return;
    }

    if (_isTracking) {
      // STOP TRACKING
      await _locationService.stopLocationStream();
      setState(() {
        _isTracking = false;
        _statusMessage = '🛑 Trip Ended. GPS OFF.';
      });
      _showTripSummary();
      return;
    }

    // REQUEST PERMISSION
    final status = await Permission.locationAlways.request();
    if (!status.isGranted) {
      setState(() => _statusMessage = '⚠️ Permission Denied');
      openAppSettings();
      return;
    }

    // START TRACKING
    setState(() {
      _isTracking = true;
      _statusMessage = '🚀 Starting GPS...';
      _updateCount = 0;
      _totalDistance = 0.0;
      _tripStartTime = DateTime.now();
    });

    LatLng? lastLocation;

    _locationService.startDriverLocationStream(
      busId: busId,
      driverName: _driverDetails!.driverName,
      busNumber: _driverDetails!.busNumber,
      onLocationUpdate: (position) {
        if (!mounted) return;

        final newLocation = LatLng(position.latitude, position.longitude);

        // Calculate distance traveled
        if (lastLocation != null) {
          final distance = Geolocator.distanceBetween(
            lastLocation!.latitude,
            lastLocation!.longitude,
            newLocation.latitude,
            newLocation.longitude,
          );
          _totalDistance += distance;
        }
        lastLocation = newLocation;

        // Smooth map animation
        _mapController.move(newLocation, _mapController.camera.zoom);

        setState(() {
          _currentLocation = newLocation;
          _currentSpeed = position.speed * 3.6; // m/s to km/h
          _updateCount++;
          _statusMessage =
              '🟢 LIVE | ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
        });
      },
    );
  }

  void _showTripSummary() {
    if (_tripStartTime == null) return;

    final duration = DateTime.now().difference(_tripStartTime!);
    final minutes = duration.inMinutes;

    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Trip Summary'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Duration: $minutes min'),
                Text(
                  'Distance: ${(_totalDistance / 1000).toStringAsFixed(2)} km',
                ),
                Text('Updates Sent: $_updateCount'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  @override
  void dispose() {
    _locationService.stopLocationStream();
    super.dispose();
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // Current Bus Location
    markers.add(
      Marker(
        width: MapConstants.markerSize * 1.2,
        height: MapConstants.markerSize * 1.2,
        point: _currentLocation,
        child: Container(
          decoration: BoxDecoration(
            color: _isTracking ? primaryColor : Colors.grey.shade600,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (_isTracking ? primaryColor : Colors.grey.shade600)
                    .withOpacity(0.5),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: Text(
              AppIcons.onlineBusIcon,
              style: TextStyle(
                fontSize: MapConstants.busIconFontSize,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );

    // Bus Stops
    for (final stop in _driverDetails?.stops ?? []) {
      final double? lat = stop['location']?['lat'] as double?;
      final double? lng = stop['location']?['lng'] as double?;

      if (lat != null && lng != null) {
        markers.add(
          Marker(
            width: MapConstants.markerSize,
            height: MapConstants.markerSize,
            point: LatLng(lat, lng),
            child: Text(
              AppIcons.busStopIcon,
              style: TextStyle(
                fontSize: MapConstants.stopIconFontSize,
                color: accentColor,
              ),
            ),
          ),
        );
      }
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final String busLabel = _driverDetails?.busNumber ?? '---';
    final String driverLabel = _driverDetails?.driverName ?? 'Driver';
    final List<Polyline> routePolylines =
        (_driverDetails?.routePoints ?? []).isNotEmpty
            ? [
              Polyline(
                points: _driverDetails!.routePoints,
                strokeWidth: 5.0,
                color: accentColor.withOpacity(0.8),
                borderStrokeWidth: 2.0,
                borderColor: Colors.black.withOpacity(0.2),
              ),
            ]
            : [];

    return Column(
      children: [
        // PROFESSIONAL CONTROL PANEL (CARD STYLE)
        Container(
          padding: const EdgeInsets.all(20.0),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Bus & Driver Info Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Route Dashboard',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'BUS $busLabel',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      driverLabel,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: accentColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),

              // Status Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:
                      _isTracking
                          ? primaryColor.withOpacity(0.1)
                          : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color:
                        _isTracking
                            ? primaryColor.withOpacity(0.5)
                            : Colors.grey.shade300,
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      _statusMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color:
                            _isTracking
                                ? darkPrimaryColor // Use the new dark color for status
                                : Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if (_isTracking) ...[
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatChip(
                            'Speed',
                            '${_currentSpeed.toStringAsFixed(1)} km/h',
                            Icons.speed,
                            Colors.green,
                          ),
                          _buildStatChip(
                            'Updates',
                            '$_updateCount',
                            Icons.update,
                            Colors.green,
                          ),
                          _buildStatChip(
                            'Distance',
                            '${(_totalDistance / 1000).toStringAsFixed(2)} km',
                            Icons.route,
                            Colors.green,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 15),

              // Control Buttons (Start/End & Reload)
              Row(
                children: [
                  // MANUAL RELOAD BUTTON
                  Container(
                    margin: const EdgeInsets.only(right: 12),
                    child: ElevatedButton(
                      onPressed: _fetchDriverDetails,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.all(16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 4,
                        minimumSize: const Size(50, 50),
                      ),
                      child: const Icon(Icons.refresh, size: 24),
                    ),
                  ),
                  // START/END TRIP BUTTON
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _toggleTracking,
                      icon: Icon(
                        _isTracking
                            ? Icons.stop_circle
                            : Icons.play_circle_filled,
                        size: 24,
                      ),
                      label: Text(
                        _isTracking ? 'END TRIP' : 'START TRACKING',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _isTracking ? Colors.red.shade600 : primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          vertical: 18,
                          horizontal: 32,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // MAP
        Expanded(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation,
              initialZoom: MapConstants.defaultMapZoom,
              maxZoom: 19,
              minZoom: 10,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
              ),
              PolylineLayer(polylines: routePolylines),
              MarkerLayer(markers: _buildMarkers()),
            ],
          ),
        ),
      ],
    );
  }

  // Helper function for stat chips (Corrected to use standard colors safely)
  Widget _buildStatChip(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, size: 18, color: primaryColor),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: darkPrimaryColor,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}
