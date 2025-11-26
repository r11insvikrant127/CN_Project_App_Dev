import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'student_lookup_screen.dart';
import 'food_menu_screen.dart';
import 'app_themes.dart';
import 'voice_command_mixin.dart';
import 'biometric_auth_service.dart';
import 'biometric_auth_widget.dart';

const String kBaseUrl = "http://192.168.29.119:5000";
//const String kBaseUrl = "http://10.20.55.59:5000";

class SubroleAuthenticationScreen extends StatefulWidget {
  final String mainRole;

  SubroleAuthenticationScreen({required this.mainRole});

  @override
  _SubroleAuthenticationScreenState createState() => _SubroleAuthenticationScreenState();
}

class _SubroleAuthenticationScreenState extends State<SubroleAuthenticationScreen> with VoiceCommandMixin {
  final TextEditingController _uniqueIdController = TextEditingController();
  bool _isLoading = false;
  String _statusMessage = '';
  bool _isSuccess = false;
  bool _isError = false;
  String _lastSelectedHostel = 'A';
  
  // Biometric related variables
  bool _showBiometricOption = false;
  bool _isBiometricAuth = false;
  String? _biometricToken;

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
    _initializeBiometricService();
  }

  Future<void> _initializeBiometricService() async {
    await BiometricAuthService.init();
  }

  Future<void> _checkBiometricAvailability() async {
    final status = await BiometricAuthService.checkBiometricStatus();
    setState(() {
      _showBiometricOption = status['hasBiometrics'] == true;
    });
  }

  @override
  Map<String, VoidCallback> getVoiceCommands() {
    Map<String, VoidCallback> commands = {
      'hostel a': () => _showAuthenticationOptions('A'),
      'hostel b': () => _showAuthenticationOptions('B'),
      'hostel c': () => _showAuthenticationOptions('C'),
      'hostel d': () => _showAuthenticationOptions('D'),
      'hostel one': () => _showAuthenticationOptions('A'),
      'hostel two': () => _showAuthenticationOptions('B'),
      'hostel three': () => _showAuthenticationOptions('C'),
      'hostel four': () => _showAuthenticationOptions('D'),
      
      // ENHANCED DIRECT AUTHENTICATION COMMANDS WITH MORE VARIATIONS
      'authenticate a': () => _showAuthenticationOptions('A'),
      'authenticate b': () => _showAuthenticationOptions('B'),
      'authenticate c': () => _showAuthenticationOptions('C'),
      'authenticate d': () => _showAuthenticationOptions('D'),
      'authenticate hostel a': () => _showAuthenticationOptions('A'),
      'authenticate hostel b': () => _showAuthenticationOptions('B'),
      'authenticate hostel c': () => _showAuthenticationOptions('C'),
      'authenticate hostel d': () => _showAuthenticationOptions('D'),
      'auth a': () => _showAuthenticationOptions('A'),
      'auth b': () => _showAuthenticationOptions('B'),
      'auth c': () => _showAuthenticationOptions('C'),
      'auth d': () => _showAuthenticationOptions('D'),
      'open a': () => _showAuthenticationOptions('A'),
      'open b': () => _showAuthenticationOptions('B'),
      'open c': () => _showAuthenticationOptions('C'),
      'open d': () => _showAuthenticationOptions('D'),
      'select a': () => _showAuthenticationOptions('A'),
      'select b': () => _showAuthenticationOptions('B'),
      'select c': () => _showAuthenticationOptions('C'),
      'select d': () => _showAuthenticationOptions('D'),
      
      // Biometric commands
      'use fingerprint': _triggerBiometricAuth,
      'use biometric': _triggerBiometricAuth,
      'fingerprint': _triggerBiometricAuth,
      'biometric': _triggerBiometricAuth,
      'scan fingerprint': _triggerBiometricAuth,
      
      'go back': () => Navigator.of(context).pop(),
      'help': _showVoiceHelpDialog,
      'dark': () => switchToDarkTheme(),
      'dark theme': () => switchToDarkTheme(),
      'light': () => switchToLightTheme(),
      'light theme': () => switchToLightTheme(),
      'switch theme': toggleTheme,
      'toggle theme': toggleTheme,
      
      // Generic authenticate command
      'authenticate': _triggerAuthentication,
      'submit': _triggerAuthentication,
      'confirm': _triggerAuthentication,
    };

    if (widget.mainRole == 'admin') {
      commands['authenticate admin'] = _authenticateAdmin;
      commands['admin biometric'] = () => _showAuthenticationOptions('ALL');
    }

    if (widget.mainRole == 'canteen') {
      commands['view menu'] = () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => FoodMenuScreen()),
      );
      commands['show menu'] = () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => FoodMenuScreen()),
      );
      commands['food menu'] = () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => FoodMenuScreen()),
      );
    }

    return commands;
  }

  void _showVoiceHelpDialog() {
    showVoiceHelp();
  }

  void _triggerBiometricAuth() {
    if (widget.mainRole != 'admin' && _lastSelectedHostel.isNotEmpty) {
      _showAuthenticationOptions(_lastSelectedHostel);
    } else if (widget.mainRole == 'admin') {
      _showAuthenticationOptions('ALL');
    } else {
      _showStatusMessage('Please select a hostel first (say "hostel A/B/C/D")', isError: true);
    }
  }

  void _triggerAuthentication() {
    // For admin role with direct auth
    if (widget.mainRole == 'admin' && _uniqueIdController.text.isNotEmpty) {
      _authenticateAdmin();
    }
    // For other roles - if we have a hostel selected, authenticate directly
    else if (widget.mainRole != 'admin' && _lastSelectedHostel.isNotEmpty) {
      _showAuthenticationOptions(_lastSelectedHostel);
    } else {
      _showStatusMessage('Please select a hostel first (say "hostel A/B/C/D")', isError: true);
    }
  }

  void _showVoiceHelp() {
    String commands = 'Available commands: "hostel a/b/c/d", "authenticate a/b/c/d", "auth a/b/c/d", "use fingerprint", "biometric", "go back", "help"';
    
    if (widget.mainRole == 'admin') {
      commands += ', "authenticate admin", "admin biometric"';
    }
    
    if (widget.mainRole == 'canteen') {
      commands += ', "view menu", "show menu", "food menu"';
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(commands),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    return buildVoiceCommandUI(
      Scaffold(
        appBar: AppBar(
          title: Text(
            widget.mainRole == 'admin' 
              ? 'Admin Authentication' 
              : '${widget.mainRole.toUpperCase()} - Hostel Authentication',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
          backgroundColor: _getRoleColor(widget.mainRole),
          actions: [
            buildVoiceCommandButton(),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.mainRole != 'admin') ...[
                          Text(
                            'Select Hostel:', 
                            style: TextStyle(
                              fontSize: 16, 
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          SizedBox(height: 16),
                        ],
                        
                        // Main content area with fixed height
                        Container(
                          height: constraints.maxHeight * 0.7,
                          child: widget.mainRole == 'admin' 
                              ? _buildAdminDirectAuth(isDark)
                              : _buildHostelGrid(isDark),
                        ),
                        // Status Message - FIX OVERFLOW HERE
                        if (_statusMessage.isNotEmpty) 
                          Container(
                            width: double.infinity,
                            margin: EdgeInsets.only(top: 10, bottom: 10),
                            child: AnimatedContainer(
                              duration: Duration(milliseconds: 300),
                              padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                              decoration: BoxDecoration(
                                color: _isSuccess 
                                ? Colors.green[50]!
                                : _isError
                                ? Colors.red[50]!
                                : Colors.blue[50]!,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _isSuccess 
                                  ? Colors.green[200]!
                                  : _isError
                                  ? Colors.red[200]!
                                  : Colors.blue[200]!,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _isSuccess 
                                    ? Icons.check_circle 
                                    : _isError
                                    ? Icons.error
                                    : Icons.info,
                                    color: _isSuccess 
                                    ? Colors.green 
                                    : _isError
                                    ? Colors.red
                                    : Colors.blue,
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _statusMessage,
                                      style: TextStyle(
                                        color: _isSuccess 
                                        ? Colors.green[800] 
                                        : _isError
                                        ? Colors.red[800]
                                        : Colors.blue[800],
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (_isLoading)
                          Container(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHostelGrid(bool isDark) {
    return Column(
      children: [
        Expanded(
          child: GridView.count(
            crossAxisCount: 2,
            childAspectRatio: 1.5,
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            children: [
              _buildHostelCard('A', isDark),
              _buildHostelCard('B', isDark),
              _buildHostelCard('C', isDark),
              _buildHostelCard('D', isDark),
            ],
          ),
        ),

        // Show Menu Button ONLY for canteen role
        if (widget.mainRole == 'canteen') ...[
          SizedBox(height: 20),
          _buildMenuButton(isDark),
        ],
      ],
    );
  }

  Widget _buildMenuButton(bool isDark) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20),
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => FoodMenuScreen()),
          );
        },
        icon: Icon(Icons.restaurant_menu, size: 24),
        label: Text('View Weekly Food Menu', style: TextStyle(fontSize: 16)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange[600],
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(vertical: 15, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 3,
        ),
      ),
    );
  }

  Widget _buildAdminDirectAuth(bool isDark) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: 20),
              Icon(Icons.admin_panel_settings, size: 80, color: Theme.of(context).colorScheme.primary),
              SizedBox(height: 20),
              Text(
                'Admin Authentication',
                style: TextStyle(
                  fontSize: 20, 
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Choose your authentication method',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              SizedBox(height: 30),
              
              // Biometric Option for Admin
              if (_showBiometricOption)
                BiometricAuthWidget(
                  role: 'admin',
                  hostel: 'ALL',
                  onSuccess: (token) {
                    _handleBiometricSuccess('ALL', token);
                  },
                  onError: (error) {
                    _showStatusMessage(error, isError: true);
                  },
                  onFallback: () {
                    _showUniqueIdAuth('ALL');
                  },
                ),
              
              if (_showBiometricOption) 
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('OR', style: TextStyle(color: Colors.grey)),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                ),
              
              // Unique ID Option for Admin
              Container(
                width: double.infinity,
                child: Card(
                  elevation: 2,
                  child: InkWell(
                    onTap: () {
                      _showUniqueIdAuth('ALL');
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue[100],
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.vpn_key, color: Colors.blue[800]),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Use Unique ID',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Authenticate with admin unique ID',
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
              ),
              SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHostelCard(String hostel, bool isDark) {
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: () {
          _showAuthenticationOptions(hostel);
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.home, size: 40, color: _getHostelColor(hostel)),
            SizedBox(height: 8),
            Text(
              '${widget.mainRole.toUpperCase()} $hostel', 
              textAlign: TextAlign.center, 
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            SizedBox(height: 4),
            if (_showBiometricOption)
              FutureBuilder<bool>(
                future: _isBiometricSetupForHostel(hostel),
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data == true) {
                    return Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fingerprint, size: 10, color: Colors.green),
                          SizedBox(width: 2),
                          Text(
                            'Fingerprint Ready',
                            style: TextStyle(fontSize: 8, color: Colors.green[800], fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    );
                  }
                  return SizedBox.shrink();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<bool> _isBiometricSetupForHostel(String hostel) async {
    final fullRole = '${widget.mainRole}_${hostel.toLowerCase()}';
    return await BiometricAuthService.isBiometricSetupCompleteForRole(fullRole);
  }

  // NEW: Show authentication options (biometric vs unique ID)
  void _showAuthenticationOptions(String hostel) {
    _lastSelectedHostel = hostel;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Authentication Method',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
              SizedBox(height: 16),
              
              if (_showBiometricOption) 
                BiometricAuthWidget(
                  role: widget.mainRole,
                  hostel: hostel,
                  onSuccess: (token) {
                    Navigator.of(context).pop();
                    _handleBiometricSuccess(hostel, token);
                  },
                  onError: (error) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(error)),
                    );
                  },
                  onFallback: () {
                    Navigator.of(context).pop();
                    _showUniqueIdAuth(hostel);
                  },
                ),
              
              if (_showBiometricOption) 
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('OR', style: TextStyle(color: Colors.grey)),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                ),
              
              // Unique ID Option
              Container(
                width: double.infinity,
                child: Card(
                  elevation: 2,
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                      _showUniqueIdAuth(hostel);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue[100],
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.vpn_key, color: Colors.blue[800]),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Use Unique ID',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Authenticate with your unique identifier',
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
              ),
              SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  // NEW: Handle biometric authentication success
  void _handleBiometricSuccess(String hostel, String token) {
    setState(() {
      _isLoading = true;
      _isSuccess = false;
      _isError = false;
      _statusMessage = 'Biometric authentication successful...';
      _isBiometricAuth = true;
      _biometricToken = token;
    });

    // Use the token from biometric auth to proceed
    _proceedWithBiometricAuthentication(hostel);
  }

  // MODIFIED: Show unique ID authentication (existing bottom sheet)
  void _showUniqueIdAuth(String hostel) {
    TextEditingController bottomSheetController = TextEditingController();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Enter Unique ID',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
              SizedBox(height: 16),
              Text(
                'Enter unique ID for ${widget.mainRole.toUpperCase()} $hostel:',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: bottomSheetController,
                obscureText: true,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Unique ID',
                  hintText: 'Enter your unique ID',
                ),
              ),
              SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: Text('Cancel'),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (bottomSheetController.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Please enter unique ID')),
                          );
                          return;
                        }
                        Navigator.of(context).pop();
                        _uniqueIdController.text = bottomSheetController.text;
                        _authenticateSubrole(hostel);
                      },
                      child: Text('Authenticate'),
                    ),
                  ),
                ],
              ),
              SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 10),
            ],
          ),
        );
      },
    ).then((_) {
      bottomSheetController.clear();
    });
  }

  // MODIFIED: Update authentication method to store biometric token
  Future<void> _authenticateSubrole(String hostel) async {
    if (_uniqueIdController.text.isEmpty && !_isBiometricAuth) {
      _showStatusMessage('Please enter unique ID', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
      _isSuccess = false;
      _isError = false;
      _statusMessage = _isBiometricAuth ? 'Verifying biometric...' : 'Authenticating...';
    });

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? deviceId = prefs.getString('device_id');

      String subrole = widget.mainRole == 'admin' 
          ? 'admin' 
          : '${widget.mainRole}_${hostel.toLowerCase()}';

      final response = await http.post(
        Uri.parse('$kBaseUrl/api/authenticate-subrole'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'device_id': deviceId,
          'main_role': widget.mainRole,
          'subrole': subrole,
          'unique_id': _isBiometricAuth ? 'biometric_auth' : _uniqueIdController.text,
          'biometric_verified': _isBiometricAuth,
        }),
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['authenticated'] == true) {
          final accessToken = data['access_token'];
          
          // Store session token for biometric auth if this was unique ID login
          if (!_isBiometricAuth) {
            await BiometricAuthService.storeSessionTokenForRole(subrole, accessToken);
          }
          
          await prefs.setString('access_token', accessToken);
          await prefs.setString('current_role', subrole);
          await prefs.setString('current_hostel', hostel);
          await prefs.setString('username', data['username'] ?? subrole);
          
          _showStatusMessage('Authentication Successful!', isSuccess: true);
          
          Future.delayed(Duration(seconds: 1), () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => StudentLookupScreen(
                  selectedRole: subrole,
                  selectedHostel: hostel,
                ),
              ),
            );
          });
        } else {
          _showStatusMessage('Authentication failed. Please try again.', isError: true);
        }
      } else if (response.statusCode == 401) {
        _showStatusMessage('Authentication failed. Please check your credentials.', isError: true);
      } else if (response.statusCode == 400) {
        _showStatusMessage('Invalid subrole. Please contact administrator.', isError: true);
      } else {
        _showStatusMessage('Authentication error. Please try again.', isError: true);
      }
    } catch (e) {
      _showStatusMessage('Network error. Please check your connection.', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
        _isBiometricAuth = false;
        _biometricToken = null;
      });
      _uniqueIdController.clear();
    }
  }

  // NEW: Helper method to proceed with biometric authentication
  void _proceedWithBiometricAuthentication(String hostel) {
    // For biometric auth, we need to call the authenticate method
    // The biometric token is already stored, so we just need to trigger the auth flow
    _authenticateSubrole(hostel);
  }

  void _authenticateAdmin() {
    if (_uniqueIdController.text.isEmpty && !_isBiometricAuth) {
      _showStatusMessage('Please enter admin unique ID', isError: true);
      return;
    }
    _authenticateSubrole('ALL');
  }

  void _showStatusMessage(String message, {bool isSuccess = false, bool isError = false}) {
    setState(() {
      _statusMessage = message;
      _isSuccess = isSuccess;
      _isError = isError;
    });
  }

  Color _getRoleColor(String role) {
    return AppThemes.getRoleColor(role, context);
  }

  Color _getHostelColor(String hostel) {
    return AppThemes.getHostelColor(hostel, context);
  }

  @override
  Map<String, String> getVoiceCommandDescriptions() {
    Map<String, String> descriptions = {
      'hostel a': 'Select Hostel A for authentication',
      'hostel b': 'Select Hostel B for authentication',
      'hostel c': 'Select Hostel C for authentication',
      'hostel d': 'Select Hostel D for authentication',
      'hostel one': 'Alternative command for Hostel A',
      'hostel two': 'Alternative command for Hostel B',
      'hostel three': 'Alternative command for Hostel C',
      'hostel four': 'Alternative command for Hostel D',
      
      // ENHANCED DIRECT AUTHENTICATION COMMAND DESCRIPTIONS
      'authenticate a': 'Directly open authentication for Hostel A',
      'authenticate b': 'Directly open authentication for Hostel B', 
      'authenticate c': 'Directly open authentication for Hostel C',
      'authenticate d': 'Directly open authentication for Hostel D',
      'authenticate hostel a': 'Directly open authentication for Hostel A',
      'authenticate hostel b': 'Directly open authentication for Hostel B',
      'authenticate hostel c': 'Directly open authentication for Hostel C', 
      'authenticate hostel d': 'Directly open authentication for Hostel D',
      'auth a': 'Short command for Hostel A authentication',
      'auth b': 'Short command for Hostel B authentication',
      'auth c': 'Short command for Hostel C authentication',
      'auth d': 'Short command for Hostel D authentication',
      'open a': 'Open authentication for Hostel A',
      'open b': 'Open authentication for Hostel B',
      'open c': 'Open authentication for Hostel C',
      'open d': 'Open authentication for Hostel D',
      'select a': 'Select Hostel A for authentication',
      'select b': 'Select Hostel B for authentication',
      'select c': 'Select Hostel C for authentication',
      'select d': 'Select Hostel D for authentication',
      
      // Biometric commands
      'use fingerprint': 'Use fingerprint authentication for selected hostel',
      'use biometric': 'Use biometric authentication for selected hostel',
      'fingerprint': 'Short command for fingerprint authentication',
      'biometric': 'Short command for biometric authentication',
      'scan fingerprint': 'Initiate fingerprint scanning',
      
      'go back': 'Return to role selection screen',
      'help': 'Show this help dialog',
      'dark': 'Switch to dark theme',
      'dark theme': 'Switch to dark theme',
      'light': 'Switch to light theme',
      'light theme': 'Switch to light theme',
      'switch theme': 'Toggle between dark and light themes',
      'toggle theme': 'Toggle between dark and light themes',
      
      // UPDATED DESCRIPTIONS
      'authenticate': 'Open authentication for selected hostel',
      'submit': 'Submit authentication with entered ID',
      'confirm': 'Submit authentication with entered ID',
    };

    if (widget.mainRole == 'admin') {
      descriptions['authenticate admin'] = 'Start admin authentication process';
      descriptions['admin biometric'] = 'Use biometric authentication for admin';
    }

    if (widget.mainRole == 'canteen') {
      descriptions['view menu'] = 'Open weekly food menu';
      descriptions['show menu'] = 'Open weekly food menu';
      descriptions['food menu'] = 'Open weekly food menu';
    }

    return descriptions;
  }
}
