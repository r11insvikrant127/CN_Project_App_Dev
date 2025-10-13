//biometric_auth_service.dart

import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BiometricAuthService {
  static final LocalAuthentication _auth = LocalAuthentication();
  static final FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static late SharedPreferences _prefs;

  // Initialize service
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Storage keys
  static const String _sessionTokenKey = 'session_token';
  static const String _biometricEnabledKey = 'biometric_enabled';
  static const String _isBiometricSetupKey = 'biometric_setup_complete';

  // Check if biometric is available
  static Future<Map<String, dynamic>> checkBiometricStatus() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      final availableBiometrics = await _auth.getAvailableBiometrics();
      
      bool hasFingerprint = availableBiometrics.contains(BiometricType.strong) ||
                           availableBiometrics.contains(BiometricType.weak) ||
                           availableBiometrics.contains(BiometricType.fingerprint);

      return {
        'canCheck': canCheck,
        'isSupported': isSupported,
        'hasBiometrics': hasFingerprint,
        'availableTypes': availableBiometrics,
        'message': hasFingerprint ? 
            'Fingerprint ready ✅' : 
            'No fingerprints registered on device',
      };
    } catch (e) {
      return {
        'canCheck': false,
        'isSupported': false,
        'hasBiometrics': false,
        'availableTypes': [],
        'message': 'Error checking biometric status: $e',
      };
    }
  }

  // Check if biometric is enabled
  static bool get isBiometricEnabled {
    return _prefs.getBool(_biometricEnabledKey) ?? false;
  }

  // Check if biometric setup is complete (user has stored a token)
  static Future<bool> get isBiometricSetupComplete async {
    final token = await _secureStorage.read(key: _sessionTokenKey);
    return token != null && _prefs.getBool(_isBiometricSetupKey) == true;
  }

  // Enable/disable biometric authentication
  static Future<void> setBiometricEnabled(bool enabled) async {
    await _prefs.setBool(_biometricEnabledKey, enabled);
    
    if (!enabled) {
      // Clear secure storage when disabling biometric
      await _secureStorage.delete(key: _sessionTokenKey);
      await _prefs.setBool(_isBiometricSetupKey, false);
    }
  }

  // Store session token in secure storage (called after successful credential login)
  static Future<void> storeSessionToken(String token) async {
    await _secureStorage.write(key: _sessionTokenKey, value: token);
    await _prefs.setBool(_isBiometricSetupKey, true);
    await _prefs.setBool(_biometricEnabledKey, true);
  }

  // Get session token from secure storage (requires biometric auth)
  static Future<Map<String, dynamic>> getSessionTokenWithBiometric({
    String reason = 'Authenticate to access your account'
  }) async {
    try {
      // First check if biometric is available
      final status = await checkBiometricStatus();
      if (!status['isSupported'] || !status['hasBiometrics']) {
        return {
          'success': false,
          'token': null,
          'message': 'Biometric authentication not available on this device',
          'error': 'biometric_not_available',
        };
      }

      // Verify biometric
      final biometricResult = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          sensitiveTransaction: true,
          useErrorDialogs: true, // Show system error dialogs
        ),
      );

      if (biometricResult) {
        // Biometric successful, retrieve token from secure storage
        final token = await _secureStorage.read(key: _sessionTokenKey);
        
        if (token != null && token.isNotEmpty) {
          return {
            'success': true,
            'token': token,
            'message': 'Authentication successful',
          };
        } else {
          return {
            'success': false,
            'token': null,
            'message': 'No session token found. Please use device verification first.',
            'error': 'no_token',
          };
        }
      } else {
        return {
          'success': false,
          'token': null,
          'message': 'Authentication cancelled or failed',
          'error': 'authentication_failed',
        };
      }
    } catch (e) {
      print('Biometric auth error: $e');
      
      String errorMessage = 'Authentication error';
      String errorType = 'unknown_error';
      
      if (e.toString().contains('FragmentActivity')) {
        errorMessage = 'Fingerprint authentication requires app configuration. Please use device verification.';
        errorType = 'configuration_error';
      } else if (e.toString().contains('NotAvailable')) {
        errorMessage = 'Fingerprint authentication not available';
        errorType = 'not_available';
      } else if (e.toString().contains('PasscodeNotSet')) {
        errorMessage = 'Please set up device lock screen to use fingerprint';
        errorType = 'passcode_not_set';
      }
      
      return {
        'success': false,
        'token': null,
        'message': errorMessage,
        'error': errorType,
      };
    }
  }

  // Get stored token without biometric (for immediate use after device verification)
  static Future<String?> getStoredToken() async {
    try {
      return await _secureStorage.read(key: _sessionTokenKey);
    } catch (e) {
      print('Error reading stored token: $e');
      return null;
    }
  }

  // Clear all biometric data
  static Future<void> clearBiometricData() async {
    await _secureStorage.delete(key: _sessionTokenKey);
    await _prefs.setBool(_isBiometricSetupKey, false);
    await _prefs.setBool(_biometricEnabledKey, false);
  }

  // Check if we have a valid session (for auto-login)
  static Future<bool> hasValidSession() async {
    if (!isBiometricEnabled) return false;
    
    final token = await _secureStorage.read(key: _sessionTokenKey);
    return token != null && token.isNotEmpty;
  }
}
