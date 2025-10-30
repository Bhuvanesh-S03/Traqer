// --- lib/models/bus_model.dart ---

import 'package:cloud_firestore/cloud_firestore.dart';

class StopModel {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final int order;

  StopModel({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.order,
  });

  factory StopModel.fromMap(Map<String, dynamic> data) {
    return StopModel(
      id: data['id'] ?? '',
      name: data['name'] ?? 'Unnamed Stop',
      order: data['order'] ?? 0,
      // Safely handle nested 'location' map
      lat: (data['location']?['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (data['location']?['lng'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class BusModel {
  final String id;
  final String busNumber;
  final String routeName;
  final String? driverName;
  final List<StopModel> stops;

  BusModel({
    required this.id,
    required this.busNumber,
    required this.routeName,
    this.driverName,
    required this.stops,
  });

  factory BusModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      throw Exception("Bus document data is null");
    }

    // Safely parse the list of stops
    final List<dynamic> stopsList = data['stops'] ?? [];
    final List<StopModel> parsedStops =
        stopsList
            .map(
              (stopMap) => StopModel.fromMap(stopMap as Map<String, dynamic>),
            )
            .toList();

    return BusModel(
      id: doc.id,
      busNumber: data['busNumber'] ?? 'N/A',
      routeName: data['routeName'] ?? 'Unknown Route',
      driverName: data['driverName'],
      stops: parsedStops,
    );
  }
}
