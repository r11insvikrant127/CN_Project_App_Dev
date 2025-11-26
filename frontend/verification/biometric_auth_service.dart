// biometric_auth_service.dart - UPDATED

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
  static const String _roleBiometricKey = 'biometric_role_';

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

  // Check if biometric is enabled for a specific role
  static bool isBiometricEnabledForRole(String role) {
    return _prefs.getBool('$_roleBiometricKey$role') ?? false;
  }

  // Enable/disable biometric for a specific role
  static Future<void> setBiometricEnabledForRole(String role, bool enabled) async {
    await _prefs.setBool('$_roleBiometricKey$role', enabled);
    
    if (!enabled) {
      // Clear role-specific biometric data when disabling
      await _secureStorage.delete(key: '${_sessionTokenKey}_$role');
    }
  }

  // Store session token for specific role in secure storage
  static Future<void> storeSessionTokenForRole(String role, String token) async {
    await _secureStorage.write(key: '${_sessionTokenKey}_$role', value: token);
    await _prefs.setBool('$_roleBiometricKey$role', true);
    await _prefs.setBool(_isBiometricSetupKey, true);
  }

  // Get session token for specific role (requires biometric auth)
  static Future<Map<String, dynamic>> getSessionTokenForRoleWithBiometric({
    required String role,
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
          useErrorDialogs: true,
        ),
      );

      if (biometricResult) {
        // Biometric successful, retrieve token from secure storage
        final token = await _secureStorage.read(key: '${_sessionTokenKey}_$role');
        
        if (token != null && token.isNotEmpty) {
          return {
            'success': true,
            'token': token,
            'message': 'Biometric authentication successful',
            'role': role,
          };
        } else {
          return {
            'success': false,
            'token': null,
            'message': 'No session token found for this role. Please use unique ID first.',
            'error': 'no_token',
          };
        }
      } else {
        return {
          'success': false,
          'token': null,
          'message': 'Biometric authentication cancelled or failed',
          'error': 'authentication_failed',
        };
      }
    } catch (e) {
      print('Biometric auth error for role $role: $e');
      
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

  // Check if biometric setup is complete for a role
  static Future<bool> isBiometricSetupCompleteForRole(String role) async {
    final token = await _secureStorage.read(key: '${_sessionTokenKey}_$role');
    return token != null && _prefs.getBool('$_roleBiometricKey$role') == true;
  }

  // Clear biometric data for specific role
  static Future<void> clearBiometricDataForRole(String role) async {
    await _secureStorage.delete(key: '${_sessionTokenKey}_$role');
    await _prefs.setBool('$_roleBiometricKey$role', false);
  }

  // Clear all biometric data
  static Future<void> clearAllBiometricData() async {
    final allKeys = await _secureStorage.readAll();
    for (final key in allKeys.keys) {
      if (key.startsWith(_sessionTokenKey)) {
        await _secureStorage.delete(key: key);
      }
    }
    await _prefs.setBool(_isBiometricSetupKey, false);
    await _prefs.setBool(_biometricEnabledKey, false);
    
    // Clear all role-specific biometric settings
    final keys = _prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith(_roleBiometricKey)) {
        await _prefs.remove(key);
      }
    }
  }
}
