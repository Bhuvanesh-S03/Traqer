// --- lib/utils/constants.dart ---

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

// 1. Icon Definitions (Using Unicode/Text)
class AppIcons {
  static const String onlineBusIcon = '🚌';
  static const String offlineBusIcon = '❌';
  static const String busStopIcon = '📍';
}

// 2. Map Constants
class MapConstants {
  static const LatLng defaultMapCenter = LatLng(11.94, 79.83); // Pondicherry
  static const double defaultMapZoom = 14.5; // Increased zoom for better detail
  static const int offlineThresholdMs = 180000; // 3 minutes in milliseconds
  static const double markerSize = 35.0;
  static const double busIconFontSize = 28.0;
  static const double stopIconFontSize = 22.0;
}

// 3. Colors for clarity
class AppColors {
  static const Color assignedBusColor = Color(0xFF4CAF50); // Green
  static const Color otherBusColor = Color(0xFF2196F3); // Blue
  static const Color offlineBusColor = Color(0xFFF44336); // Red
  static const Color busStopColor = Color(0xFFFFEB3B); // Yellow
}

// 4. Route Model
class BusRoute {
  final String busId;
  final String busNumber;
  final String routeName;
  final List<LatLng> polylinePoints;
  final List<Map<String, dynamic>> stops;

  BusRoute({
    required this.busId,
    required this.busNumber,
    required this.routeName,
    required this.polylinePoints,
    required this.stops,
  });
}
