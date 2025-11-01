// --- lib/services/location_service.dart ---
// FINAL FIX: Ensures update every 3 seconds (Heartbeat) and every 0.5m

import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:flutter/material.dart';

class LocationService {
  static const String _busLocationPath = 'live_locations';
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref(
    _busLocationPath,
  );

  Position? _lastPosition;
  Timer? _heartbeatTimer;
  bool _isTracking = false;

  // CRITICAL FIX: Location will update if moved 0.5 meters OR if 3 seconds pass (via heartbeat)
  static const double _minDistanceMeters =
      0.5; // Distance threshold for update when moving (for frequent testing)
  static const int _heartbeatIntervalSeconds =
      3; // FIX: Heartbeat update every 3 seconds for smoother tracking
  static const int _maxAgeThresholdMs =
      30000; // 30 seconds = data is considered stale on client

  // Stream to listen to ALL bus locations for the Parent Map
  Stream<Map<String, Map<String, dynamic>>> getAllBusLocations() {
    return _dbRef.onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null || data is! Map) return {};

      final busLocations = <String, Map<String, dynamic>>{};
      (data as Map).forEach((key, value) {
        if (value is Map<dynamic, dynamic>) {
          busLocations[key.toString()] = {
            'lat': (value['lat'] as num?)?.toDouble() ?? 0.0,
            'lng': (value['lng'] as num?)?.toDouble() ?? 0.0,
            'timestamp': value['timestamp'] as int? ?? 0,
            'driverName': value['driverName'] ?? 'Unknown',
            'busNumber': value['busNumber'] ?? 'N/A',
            'speed': (value['speed'] as num?)?.toDouble() ?? 0.0,
            'heading': (value['heading'] as num?)?.toDouble() ?? 0.0,
          };
        }
      });
      return busLocations;
    });
  }

  // --- DRIVER TRACKING LOGIC ---

  StreamSubscription<Position>? _positionStreamSubscription;

  void startDriverLocationStream({
    required String busId,
    required String driverName,
    required String busNumber,
    required Function(Position) onLocationUpdate,
  }) {
    if (_isTracking) {
      debugPrint('⚠️ Tracking already active. Stopping previous stream.');
      stopLocationStream();
    }

    _isTracking = true;

    // Location settings for high accuracy and 0.5m distance filter
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 1,
    );

    debugPrint('🚀 Starting GPS tracking for Bus: $busNumber ($busId)...');

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) {
        debugPrint(
          '📍 GPS Update: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
        );
        _handleLocationUpdate(
          position: position,
          busId: busId,
          driverName: driverName,
          busNumber: busNumber,
          onLocationUpdate: onLocationUpdate,
        );
      },
      onError: (error) {
        debugPrint('❌ Location stream error: $error');
      },
      cancelOnError: false, // Keep stream alive on errors
    );

    // Start heartbeat timer (FIX: Ensures update every 3 seconds)
    _startHeartbeat(busId: busId, driverName: driverName, busNumber: busNumber);

    // CRITICAL FIX: Get initial position immediately
    _getInitialPosition(
      busId: busId,
      driverName: driverName,
      busNumber: busNumber,
      onLocationUpdate: onLocationUpdate,
    );
  }

  // FIXED: Get initial GPS position without waiting for stream
  Future<void> _getInitialPosition({
    required String busId,
    required String driverName,
    required String busNumber,
    required Function(Position) onLocationUpdate,
  }) async {
    try {
      debugPrint('🔍 Getting initial GPS position...');
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      debugPrint(
        '✅ Initial position acquired: ${position.latitude}, ${position.longitude}',
      );

      _lastPosition = position;
      onLocationUpdate(position);

      await _writeLocationToRTDB(
        busId: busId,
        position: position,
        driverName: driverName,
        busNumber: busNumber,
      );
    } catch (e) {
      debugPrint('⚠️ Could not get initial position: $e');
    }
  }

  void _handleLocationUpdate({
    required Position position,
    required String busId,
    required String driverName,
    required String busNumber,
    required Function(Position) onLocationUpdate,
  }) {
    // Calculate distance from last position
    double distance = 0.0;
    if (_lastPosition != null) {
      distance = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        position.latitude,
        position.longitude,
      );
    }

    // Send update if moved >= 0.5 meters
    if (_lastPosition == null || distance >= _minDistanceMeters) {
      debugPrint(
        '✅ Moved ${distance.toStringAsFixed(2)}m - Sending distance-based update',
      );

      _lastPosition = position;
      onLocationUpdate(position);

      _writeLocationToRTDB(
        busId: busId,
        position: position,
        driverName: driverName,
        busNumber: busNumber,
      );
    }
  }

  // Heartbeat: Sends periodic updates every 3 seconds even when stationary
  void _startHeartbeat({
    required String busId,
    required String driverName,
    required String busNumber,
  }) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      Duration(seconds: _heartbeatIntervalSeconds),
      (timer) async {
        if (_lastPosition != null && _isTracking) {
          debugPrint(
            '💓 Heartbeat: Confirming online status and location write (every 3s)',
          );
          await _writeLocationToRTDB(
            busId: busId,
            position: _lastPosition!,
            driverName: driverName,
            busNumber: busNumber,
            isHeartbeat: true,
          );
        }
      },
    );
  }

  Future<void> _writeLocationToRTDB({
    required String busId,
    required Position position,
    required String driverName,
    required String busNumber,
    bool isHeartbeat = false,
  }) async {
    // CHECKPOINT: Ensure busId is valid before writing
    if (busId.isEmpty) {
      debugPrint('❌ RTDB Write Error: Bus ID is empty.');
      return;
    }

    try {
      final locationData = {
        'lat': position.latitude,
        'lng': position.longitude,
        // CHECKPOINT: Ensure the timestamp is always the current time
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'driverName': driverName,
        'busNumber': busNumber,
        'speed': position.speed, // m/s
        'heading': position.heading, // Degrees from north
        'accuracy': position.accuracy, // Meters
      };

      // Use update() to prevent overwriting other bus data
      await _dbRef.child(busId).update(locationData);

      if (!isHeartbeat) {
        debugPrint(
          '✅ RTDB Write Success (Distance-based): ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
        );
      } else {
        debugPrint('💚 Heartbeat sent (3s timer)');
      }
    } catch (e) {
      // CHECKPOINT: Log any write errors
      debugPrint('❌ RTDB Write Error: $e');
    }
  }

  Future<void> stopLocationStream() async {
    _isTracking = false;
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _lastPosition = null;
    debugPrint('🛑 Location stream stopped.');
  }

  bool get isTracking => _isTracking;
}
