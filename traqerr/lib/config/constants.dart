// --- lib/config/constants.dart ---

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

// ====================================================================
// 1. FIREBASE CONFIGURATION
// These values are taken from your google-services.json / Firebase Console.
// ====================================================================

// CRITICAL: Explicitly define the Realtime Database URL for regional access.
const String kFirebaseDatabaseURL =
    'https://traqer-76e85-default-rtdb.asia-southeast1.firebasedatabase.app';

// The API Key from your configuration file (from google-services.json)
const String kFirebaseApiKey = 'AIzaSyBSLqVHvpvUGMbzmkg9ohZEp3v2Sm2SOT4';
const String kFirebaseAppId = '1:166593920809:android:b2838831cd0d1923a78138';
const String kFirebaseMessagingSenderId = '166593920809';
const String kFirebaseProjectId = 'traqer-76e85';
const String kFirebaseStorageBucket = 'traqer-76e85.firebasestorage.app';

// ====================================================================
// 2. CORE APP CONSTANTS (The business logic)
// ====================================================================

// Synthetic Email Domain used in Admin Portal (app.js)
const String kAuthDomain = 'traqerr.com';

// Firestore Collection Names
const String kParentsCollection = 'parents';
const String kDriversCollection = 'drivers';
const String kBusesCollection = 'buses';
const String kCircularsCollection = 'circulars';
const String kAchievementsCollection = 'achievements';

// Realtime Database Path for live GPS
const String kLiveLocationsPath = 'live_locations';

// Location and Notification Thresholds
const double kGpsUpdateDistanceFilterMeters =
    10; // Update location every 10 meters
const double kNotificationRadiusKm = 0.5; // 500 meters notification radius

// ====================================================================
// 3. THEME/AESTHETICS (from style.css: #00C896)
// ====================================================================

const Color kPrimaryColor = Color(0xFF00C896); // Teal/Green

// Function to provide FirebaseOptions object for initialization
const FirebaseOptions kFirebaseOptions = FirebaseOptions(
  apiKey: kFirebaseApiKey,
  appId: kFirebaseAppId,
  messagingSenderId: kFirebaseMessagingSenderId,
  projectId: kFirebaseProjectId,
  storageBucket: kFirebaseStorageBucket,
  databaseURL: kFirebaseDatabaseURL, // CRITICAL FIX: Pass URL here
);
