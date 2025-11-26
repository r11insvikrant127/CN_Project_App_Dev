// biometric_auth_widget.dart
import 'package:flutter/material.dart';
import 'biometric_auth_service.dart';

class BiometricAuthWidget extends StatefulWidget {
  final String role;
  final String hostel; // For subroles like super_A, canteen_B, etc.
  final Function(String) onSuccess;
  final Function(String) onError;
  final Function() onFallback;

  const BiometricAuthWidget({
    Key? key,
    required this.role,
    required this.hostel,
    required this.onSuccess,
    required this.onError,
    required this.onFallback,
  }) : super(key: key);

  @override
  _BiometricAuthWidgetState createState() => _BiometricAuthWidgetState();
}

class _BiometricAuthWidgetState extends State<BiometricAuthWidget> {
  bool _isChecking = false;
  bool _biometricAvailable = false;
  bool _biometricSetup = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricStatus();
  }

  Future<void> _checkBiometricStatus() async {
    setState(() {
      _isChecking = true;
    });

    // Check if biometric is available
    final status = await BiometricAuthService.checkBiometricStatus();
    
    // Check if biometric is already setup for this role
    final fullRole = widget.role == 'admin' ? 'admin' : '${widget.role}_${widget.hostel.toLowerCase()}';
    final isSetup = await BiometricAuthService.isBiometricSetupCompleteForRole(fullRole);

    setState(() {
      _biometricAvailable = status['hasBiometrics'] == true;
      _biometricSetup = isSetup;
      _isChecking = false;
    });
  }

  Future<void> _authenticateWithBiometric() async {
    if (!_biometricAvailable) {
      widget.onError('Biometric authentication not available on this device');
      return;
    }

    setState(() {
      _isChecking = true;
    });

    final fullRole = widget.role == 'admin' ? 'admin' : '${widget.role}_${widget.hostel.toLowerCase()}';
    
    final result = await BiometricAuthService.getSessionTokenForRoleWithBiometric(
      role: fullRole,
      reason: 'Authenticate for ${widget.role.toUpperCase()} ${widget.role == 'admin' ? '' : widget.hostel}',
    );

    setState(() {
      _isChecking = false;
    });

    if (result['success'] == true) {
      widget.onSuccess(result['token']);
    } else {
      widget.onError(result['message']);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return _buildLoadingState();
    }

    if (!_biometricAvailable) {
      return _buildUnavailableState();
    }

    if (!_biometricSetup) {
      return _buildSetupPrompt();
    }

    return _buildBiometricButton();
  }

  Widget _buildLoadingState() {
    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 8),
          Text(
            'Checking biometric status...',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildUnavailableState() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(Icons.fingerprint, size: 40, color: Colors.grey),
          SizedBox(height: 8),
          Text(
            'Biometric Unavailable',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 4),
          Text(
            'Use unique ID authentication instead',
            style: TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSetupPrompt() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        children: [
          Icon(Icons.fingerprint, size: 40, color: Colors.blue),
          SizedBox(height: 8),
          Text(
            'Setup Biometric Auth',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[800]),
          ),
          SizedBox(height: 4),
          Text(
            'Use unique ID first to enable fingerprint login for future use',
            style: TextStyle(fontSize: 12, color: Colors.blue[700]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBiometricButton() {
    return Container(
      width: double.infinity,
      child: Card(
        elevation: 2,
        child: InkWell(
          onTap: _authenticateWithBiometric,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green[100],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.fingerprint, color: Colors.green[800]),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Use Fingerprint',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Quick login with biometric authentication',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.grey[400]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
