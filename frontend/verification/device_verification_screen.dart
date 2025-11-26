import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'role_selection_screen.dart';
import 'biometric_auth_service.dart';

const String kBaseUrl = "http://192.168.29.119:5000";
//const String kBaseUrl = "http://10.20.55.59:5000";

class DeviceVerificationScreen extends StatefulWidget {
  @override
  _DeviceVerificationScreenState createState() => _DeviceVerificationScreenState();
}

class _DeviceVerificationScreenState extends State<DeviceVerificationScreen> {
  bool _isLoading = false;
  String _deviceId = '';
  String _statusMessage = 'Select authentication method';
  bool _verificationSuccess = false;
  bool _verificationFailed = false;
  String _authMethod = ''; // 'fingerprint' or 'device'
  bool _fingerprintAvailable = false;
  bool _isBiometricSetupComplete = false;
  bool _showAuthOptions = true;

  @override
  void initState() {
    super.initState();
    _initializeBiometricService();
    _checkFingerprintAvailability();
    _checkBiometricSetup();
  }

  Future<void> _initializeBiometricService() async {
    await BiometricAuthService.init();
  }

  void _checkFingerprintAvailability() async {
    final status = await BiometricAuthService.checkBiometricStatus();
    setState(() {
      _fingerprintAvailable = status['hasBiometrics'] == true;
    });
  }

  void _checkBiometricSetup() async {
    // For device verification, we'll check if any biometric is setup using a generic role
    final isSetup = await BiometricAuthService.isBiometricSetupCompleteForRole('device_verification');
    setState(() {
      _isBiometricSetupComplete = isSetup;
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // FINGERPRINT AUTHENTICATION - Fixed implementation
  Future<void> _authenticateWithFingerprint() async {
    setState(() {
      _authMethod = 'fingerprint';
      _isLoading = true;
      _showAuthOptions = false;
      _statusMessage = 'Please place your finger on the sensor...';
    });

    try {
      // Step 1: Authenticate with biometrics - using generic role for device verification
      final Map<String, dynamic> result = await BiometricAuthService.getSessionTokenForRoleWithBiometric(
        role: 'device_verification',
        reason: 'Authenticate to access Student Management System'
      );
      
      if (result['success'] == true && result['token'] != null) {
        // Step 2: Use the retrieved token to authenticate with backend
        final authSuccess = await _authenticateWithBackend(result['token'] as String);
        
        if (authSuccess) {
          setState(() {
            _isLoading = false;
            _verificationSuccess = true;
            _statusMessage = 'Fingerprint authentication successful! 🎉';
          });

          await Future.delayed(Duration(seconds: 1));
          
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => RoleSelectionScreen(authMethod: 'fingerprint')),
          );
        } else {
          setState(() {
            _isLoading = false;
            _verificationFailed = true;
            _statusMessage = 'Session expired. Please use device verification.';
          });
          // Clear invalid token
          await BiometricAuthService.clearBiometricDataForRole('device_verification');
        }
      } else {
        setState(() {
          _isLoading = false;
          _verificationFailed = true;
          _showAuthOptions = true;
          _statusMessage = result['message'] as String? ?? 'Fingerprint authentication failed';
          
          // Show detailed error dialog for specific errors
          if (result['error'] == 'no_token') {
            _showBiometricSetupDialog();
          } else if (result['error'] == 'passcode_not_set') {
            _showPasscodeSetupDialog();
          } else if (result['error'] == 'configuration_error') {
            _showConfigurationErrorDialog();
          }
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _verificationFailed = true;
        _showAuthOptions = true;
        _statusMessage = 'Authentication error: $e';
      });
    }
  }

  // DEVICE VERIFICATION - This will also setup biometric for future use
  Future<void> _verifyWithDeviceId() async {
    setState(() {
      _authMethod = 'device';
      _isLoading = true;
      _showAuthOptions = false;
      _statusMessage = 'Getting device information...';
    });

    await _getDeviceId();
    await _verifyAndSetupWithBackend();
  }

  Future<void> _getDeviceId() async {
    try {
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      
      if (Theme.of(context).platform == TargetPlatform.android) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        String deviceIdentifier = [
          androidInfo.model,
          androidInfo.manufacturer,
          androidInfo.device,
          androidInfo.product,
        ].where((item) => item != null && item.isNotEmpty).join('-');
        
        setState(() {
          _deviceId = deviceIdentifier.isNotEmpty ? 
              deviceIdentifier.replaceAll(' ', '_').toLowerCase() : 
              "android_unknown_device";
        });
      } else {
        setState(() {
          _deviceId = "ios_unknown_device";
        });
      }
      
    } catch (e) {
      setState(() {
        _deviceId = "error_getting_device_id";
        _statusMessage = 'Error getting device information';
        _verificationFailed = true;
        _isLoading = false;
        _showAuthOptions = true;
      });
    }
  }

  Future<bool> _authenticateWithBackend(String token) async {
    try {
      // Verify the token with backend
      final response = await http.get(
        Uri.parse('$kBaseUrl/api/verify-token'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      print('Token verification failed: $e');
      return false;
    }
  }

  Future<void> _verifyAndSetupWithBackend() async {
    if (_deviceId.isEmpty || _deviceId == "error_getting_device_id") {
      setState(() {
        _isLoading = false;
        _verificationFailed = true;
        _showAuthOptions = true;
        _statusMessage = 'Failed to get device ID';
      });
      return;
    }

    setState(() {
      _statusMessage = 'Verifying device with database...';
    });

    try {
      final response = await http.post(
        Uri.parse('$kBaseUrl/api/verify-device'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'device_id': _deviceId}),
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        
        if (data['verified'] == true) {
          SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setString('device_id', _deviceId);
          await prefs.setString('device_info', json.encode(data['device_info']));
          
          // ✅ USE REAL SESSION TOKEN FROM BACKEND
          final sessionToken = data['session_token'] as String?;
          if (sessionToken == null || sessionToken.isEmpty) {
            throw Exception('No session token received from server');
          }
          
          // Store session token for device verification role
          await BiometricAuthService.storeSessionTokenForRole('device_verification', sessionToken);
          await prefs.setString('token_type', data['token_type'] as String? ?? 'bearer');
          
          setState(() {
            _isLoading = false;
            _verificationSuccess = true;
            _statusMessage = 'Device verified successfully! ✅\nSecure session established.';
          });

          await Future.delayed(Duration(seconds: 2));
          
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => RoleSelectionScreen(authMethod: 'device')),
          );
          
        } else {
          setState(() {
            _isLoading = false;
            _verificationFailed = true;
            _showAuthOptions = true;
            _statusMessage = data['message'] as String? ?? 'Device not registered. Please contact admin.';
          });
        }
      } else {
        setState(() {
          _isLoading = false;
          _verificationFailed = true;
          _showAuthOptions = true;
          _statusMessage = 'Server error. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _verificationFailed = true;
        _showAuthOptions = true;
        _statusMessage = 'Network error. Please check your connection.';
      });
    }
  }

  void _retryVerification() {
    setState(() {
      _isLoading = false;
      _verificationSuccess = false;
      _verificationFailed = false;
      _showAuthOptions = true;
      _statusMessage = 'Select authentication method';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.school, color: Colors.blue),
            SizedBox(width: 12),
            Text(
              'Student Management',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    // Show full-screen verification status when verifying
    if (!_showAuthOptions) {
      return _buildVerificationScreen();
    }
    
    // Show authentication options when not verifying
    return Column(
      children: [
        // Header - Only show when showing auth options
        _buildHeader(),
        SizedBox(height: 32),
        
        // Authentication Options
        _buildAuthOptions(),
      ],
    );
  }

  Widget _buildVerificationScreen() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildStatusVisualization(),
        SizedBox(height: 32),
        _buildStatusInformation(),
        SizedBox(height: 24),
        _buildActionButtons(),
      ],
    );
  }

  Widget _buildHeader() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.blue[50]!, Colors.purple[50]!],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.security, size: 50, color: Colors.blue),
              SizedBox(height: 16),
              Text(
                'Secure Authentication',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[800],
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Choose your preferred authentication method',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
              if (_isBiometricSetupComplete) ...[
                SizedBox(height: 12),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.fingerprint, size: 16, color: Colors.green),
                      SizedBox(width: 6),
                      Text(
                        'Fingerprint Ready',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green[800],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuthOptions() {
    return Expanded(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Fingerprint Option
            if (_fingerprintAvailable && _isBiometricSetupComplete)
              _buildAuthOptionCard(
                title: 'Fingerprint Unlock',
                subtitle: 'Use your fingerprint for quick access',
                icon: Icons.fingerprint,
                color: Colors.green,
                onTap: _authenticateWithFingerprint,
              ),
            
            if (_fingerprintAvailable && _isBiometricSetupComplete) SizedBox(height: 20),
            
            // Device Verification Option
            _buildAuthOptionCard(
              title: 'Device Verification',
              subtitle: _isBiometricSetupComplete 
                  ? 'Verify device & setup fingerprint'
                  : 'Verify using device ID',
              icon: Icons.phonelink_setup,
              color: Colors.blue,
              onTap: _verifyWithDeviceId,
            ),
            
            SizedBox(height: 32),
            
            // Information
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 24),
                  SizedBox(height: 8),
                  Text(
                    _isBiometricSetupComplete
                      ? 'Fingerprint: Quick access\nDevice Verification: Re-authenticate & update'
                      : 'Device Verification will setup fingerprint for future use',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 20), // Extra padding at bottom to prevent overflow
          ],
        ),
      ),
    );
  }

  Widget _buildAuthOptionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 30, color: color),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusVisualization() {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        color: _getStatusColor().withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_isLoading)
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor()),
              strokeWidth: 4,
            ),
          Icon(
            _getStatusIcon(),
            size: 50,
            color: _getStatusColor(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusInformation() {
    return Container(
      width: double.infinity,
      child: Column(
        children: [
          Text(
            _getStatusTitle(),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: _getStatusColor(),
            ),
          ),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _getStatusColor().withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _getStatusColor().withOpacity(0.2)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(_getStatusIcon(), color: _getStatusColor()),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _statusMessage,
                        style: TextStyle(
                          fontSize: 16,
                          color: _getStatusColor(),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_authMethod == 'device' && _deviceId.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12.0),
                    child: Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.device_hub, size: 16, color: Colors.grey[600]),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Device ID: $_deviceId',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[700],
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    if (_isLoading) {
      return Column(
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
          SizedBox(height: 16),
          Text(
            _authMethod == 'fingerprint' 
              ? 'Waiting for fingerprint...' 
              : 'Verifying with server...',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      );
    }

    if (_verificationFailed) {
      return Column(
        children: [
          ElevatedButton.icon(
            onPressed: _retryVerification,
            icon: Icon(Icons.refresh),
            label: Text('Try Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
          SizedBox(height: 12),
          TextButton.icon(
            onPressed: _showContactDialog,
            icon: Icon(Icons.contact_support),
            label: Text('Contact Support'),
          ),
        ],
      );
    }

    if (_verificationSuccess) {
      return Column(
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
          ),
          SizedBox(height: 16),
          Text(
            'Redirecting...',
            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
          ),
        ],
      );
    }

    return SizedBox.shrink();
  }

  void _showContactDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.contact_support, color: Colors.blue),
            SizedBox(width: 8),
            Text('Contact Support'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Please contact the system administrator with your Device ID:'),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _deviceId,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showBiometricSetupDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.fingerprint, color: Colors.orange),
            SizedBox(width: 8),
            Text('Setup Required'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('To use fingerprint authentication, you need to:'),
            SizedBox(height: 12),
            _buildSetupStep('1. Use "Device Verification" first'),
            _buildSetupStep('2. Complete device registration'),
            _buildSetupStep('3. Then you can use fingerprint for quick login'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showPasscodeSetupDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.lock, color: Colors.orange),
            SizedBox(width: 8),
            Text('Device Security Required'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('To use fingerprint, you need to set up a device lock screen:'),
            SizedBox(height: 12),
            _buildSetupStep('1. Go to device Settings'),
            _buildSetupStep('2. Set up Screen Lock (PIN/Pattern/Password)'),
            _buildSetupStep('3. Register your fingerprint'),
            _buildSetupStep('4. Return to this app'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showConfigurationErrorDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error, color: Colors.red),
            SizedBox(width: 8),
            Text('Configuration Error'),
          ],
        ),
        content: Text('Fingerprint authentication requires app configuration. Please use device verification for now.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupStep(String step) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(Icons.arrow_right, color: Colors.blue, size: 16),
          SizedBox(width: 4),
          Expanded(child: Text(step)),
        ],
      ),
    );
  }

  String _getStatusTitle() {
    if (_verificationSuccess) return 'Success!';
    if (_isLoading) return _authMethod == 'fingerprint' ? 'Scanning' : 'Verifying';
    if (_verificationFailed) return 'Failed';
    return 'Ready';
  }

  Color _getStatusColor() {
    if (_verificationSuccess) return Colors.green;
    if (_isLoading) return Colors.blue;
    if (_verificationFailed) return Colors.red;
    return Colors.grey;
  }

  IconData _getStatusIcon() {
    if (_verificationSuccess) return Icons.verified;
    if (_isLoading) return _authMethod == 'fingerprint' ? Icons.fingerprint : Icons.security;
    if (_verificationFailed) return Icons.error_outline;
    return Icons.phonelink_setup;
  }
}
