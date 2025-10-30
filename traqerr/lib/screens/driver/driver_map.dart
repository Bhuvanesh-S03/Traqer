// --- lib/screens/driver/driver_map_tab.dart ---

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:traqerr/config/assets.dart';
import '../../services/location_service.dart';

// Model to pass necessary driver data to the LocationService ---
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
  String _statusMessage = 'Awaiting Start';
  DriverDetails? _driverDetails;
  LatLng _currentLocation = MapConstants.defaultMapCenter;

  final Color primaryColor = const Color(0xFF00C896);

  @override
  void initState() {
    super.initState();
    _fetchDriverDetails();
  }

  // Fetches the driver profile, bus information, and route/stop data (FIXED NESTED LOCATION)
  Future<void> _fetchDriverDetails() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

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

          // FIX: Access coordinates inside 'location' map
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
                ? 'Ready. Bus: $busNumber. Route has ${stops.length} stops.'
                : 'Error: No Bus assigned. Check Admin setup.';

        // Fix: Only fit bounds if routePoints is not empty
        if (routePoints.isNotEmpty) {
          _currentLocation = routePoints.first;

          final bounds = LatLngBounds.fromPoints(routePoints);
          _mapController.fitCamera(
            CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
          );
        } else {
          _mapController.move(_currentLocation, MapConstants.defaultMapZoom);
        }
      });
    }
  }

  Future<void> _toggleTracking() async {
    final busId = _driverDetails?.busId;
    if (busId == null || busId.isEmpty) {
      setState(() => _statusMessage = 'Cannot start: Bus ID not found.');
      return;
    }

    if (_isTracking) {
      _locationService.stopLocationStream();
      setState(() {
        _isTracking = false;
        _statusMessage = 'Trip Ended. GPS is OFF.';
      });
      return;
    }

    final status = await Permission.locationAlways.request();
    if (status.isGranted) {
      setState(() {
        _isTracking = true;
        _statusMessage = 'Tracking STARTED. Sending updates...';
      });

      _locationService.startDriverLocationStream(
        busId: busId,
        driverName: _driverDetails!.driverName,
        busNumber: _driverDetails!.busNumber,
        onLocationUpdate: (position) {
          if (mounted) {
            final newLocation = LatLng(position.latitude, position.longitude);
            _mapController.move(newLocation, _mapController.camera.zoom);

            setState(() {
              _currentLocation = newLocation;
              _statusMessage =
                  'LIVE Lat: ${position.latitude.toStringAsFixed(4)}, Lng: ${position.longitude.toStringAsFixed(4)}';
            });
          }
        },
      );
    } else {
      setState(
        () =>
            _statusMessage = 'Permission Denied. Set to "Allow all the time".',
      );
      openAppSettings();
    }
  }

  @override
  void dispose() {
    _locationService.stopLocationStream();
    super.dispose();
  }

  // --- Map and Marker Builder (FIXED NESTED LOCATION) ---
  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // 1. Current Bus Location Marker (Assigned/Green Icon)
    markers.add(
      Marker(
        width: MapConstants.markerSize,
        height: MapConstants.markerSize,
        point: _currentLocation,
        child: Text(
          AppIcons.onlineBusIcon,
          style: TextStyle(
            fontSize: MapConstants.busIconFontSize,
            color: AppColors.assignedBusColor,
          ),
        ),
      ),
    );

    // 2. Bus Stops Markers
    for (final stop in _driverDetails?.stops ?? []) {
      // FIX: Access coordinates inside 'location' map
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
                color: Colors.amber.shade700,
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

    // Guard against empty point list before creating the polyline
    final List<Polyline> routePolylines =
        (_driverDetails?.routePoints ?? []).isNotEmpty
            ? [
              Polyline(
                points: _driverDetails!.routePoints,
                strokeWidth: 4.0,
                color: primaryColor.withOpacity(0.8),
              ),
            ]
            : [];

    return Column(
      children: [
        // Control Panel
        Container(
          padding: const EdgeInsets.all(16.0),
          color: Colors.grey.shade50,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Assigned Bus: $busLabel',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color:
                      _isTracking ? Colors.green.shade50 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color:
                        _isTracking
                            ? Colors.green.shade800
                            : Colors.red.shade800,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _toggleTracking,
                icon: Icon(
                  _isTracking
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outline,
                ),
                label: Text(_isTracking ? 'END TRIP' : 'START ROUTE'),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _isTracking ? Colors.red.shade600 : primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 4,
                ),
              ),
            ],
          ),
        ),
        // Map View
        Expanded(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation,
              initialZoom: MapConstants.defaultMapZoom,
              maxZoom: 18,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
              ),
              // Route Polyline (Using guarded list)
              PolylineLayer(polylines: routePolylines),
              MarkerLayer(markers: _buildMarkers()),
            ],
          ),
        ),
      ],
    );
  }
}
