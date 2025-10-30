// --- lib/services/location_service.dart ---

import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:flutter/material.dart';

class LocationService {
  // CRITICAL FIX: Match the path defined in app.js: "live_locations"
  static const String _busLocationPath = 'live_locations';
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref(
    _busLocationPath,
  );

  // Stream to listen to ALL bus locations for the Parent Map
  Stream<Map<String, Map<String, dynamic>>> getAllBusLocations() {
    return _dbRef.onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null || data is! Map) {
        return {};
      }

      final busLocations = <String, Map<String, dynamic>>{};
      (data as Map).forEach((key, value) {
        if (value is Map<dynamic, dynamic>) {
          busLocations[key.toString()] = {
            'lat': value['lat'],
            'lng': value['lng'],
            'timestamp': value['timestamp'],
            'driverName': value['driverName'],
            'busNumber': value['busNumber'],
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
    if (_positionStreamSubscription != null) {
      debugPrint('Tracking already active. Stopping previous stream.');
      _positionStreamSubscription?.cancel();
    }

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      onLocationUpdate(position);
      _writeLocationToRTDB(
        busId: busId,
        position: position,
        driverName: driverName,
        busNumber: busNumber,
      );
    });
  }

  Future<void> _writeLocationToRTDB({
    required String busId,
    required Position position,
    required String driverName,
    required String busNumber,
  }) async {
    final locationData = {
      'lat': position.latitude,
      'lng': position.longitude,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'driverName': driverName,
      'busNumber': busNumber,
    };
    await _dbRef.child(busId).set(locationData);
    debugPrint(
      'RTDB Update for $busId: ${position.latitude.toStringAsFixed(4)}',
    );
  }

  void stopLocationStream() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    debugPrint('Location stream stopped.');
  }
}
