//subrole_authentication_screen.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'student_lookup_screen.dart';
import 'food_menu_screen.dart';
import 'app_themes.dart';
import 'voice_command_mixin.dart';

const String kBaseUrl = "http://192.168.29.119:5000";
//const String kBaseUrl = "http://10.47.241.1:5000";

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

  @override
  Map<String, VoidCallback> getVoiceCommands() {
    Map<String, VoidCallback> commands = {
      'hostel a': () => _showAuthenticationBottomSheet('A'),
      'hostel b': () => _showAuthenticationBottomSheet('B'),
      'hostel c': () => _showAuthenticationBottomSheet('C'),
      'hostel d': () => _showAuthenticationBottomSheet('D'),
      'hostel one': () => _showAuthenticationBottomSheet('A'),
      'hostel two': () => _showAuthenticationBottomSheet('B'),
      'hostel three': () => _showAuthenticationBottomSheet('C'),
      'hostel four': () => _showAuthenticationBottomSheet('D'),
      
      // ENHANCED DIRECT AUTHENTICATION COMMANDS WITH MORE VARIATIONS
      'authenticate a': () => _showAuthenticationBottomSheet('A'),
      'authenticate b': () => _showAuthenticationBottomSheet('B'),
      'authenticate c': () => _showAuthenticationBottomSheet('C'),
      'authenticate d': () => _showAuthenticationBottomSheet('D'),
      'authenticate hostel a': () => _showAuthenticationBottomSheet('A'),
      'authenticate hostel b': () => _showAuthenticationBottomSheet('B'),
      'authenticate hostel c': () => _showAuthenticationBottomSheet('C'),
      'authenticate hostel d': () => _showAuthenticationBottomSheet('D'),
      'auth a': () => _showAuthenticationBottomSheet('A'),
      'auth b': () => _showAuthenticationBottomSheet('B'),
      'auth c': () => _showAuthenticationBottomSheet('C'),
      'auth d': () => _showAuthenticationBottomSheet('D'),
      'open a': () => _showAuthenticationBottomSheet('A'),
      'open b': () => _showAuthenticationBottomSheet('B'),
      'open c': () => _showAuthenticationBottomSheet('C'),
      'open d': () => _showAuthenticationBottomSheet('D'),
      'select a': () => _showAuthenticationBottomSheet('A'),
      'select b': () => _showAuthenticationBottomSheet('B'),
      'select c': () => _showAuthenticationBottomSheet('C'),
      'select d': () => _showAuthenticationBottomSheet('D'),
      
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

  void _triggerAuthentication() {
    // For admin role with direct auth
    if (widget.mainRole == 'admin' && _uniqueIdController.text.isNotEmpty) {
      _authenticateAdmin();
    }
    // For other roles - if we have a hostel selected, authenticate directly
    else if (widget.mainRole != 'admin' && _lastSelectedHostel.isNotEmpty) {
      _showAuthenticationBottomSheet(_lastSelectedHostel);
    } else {
      _showStatusMessage('Please select a hostel first (say "hostel A/B/C/D")', isError: true);
    }
  }

  void _showVoiceHelp() {
    String commands = 'Available commands: "hostel a/b/c/d", "authenticate a/b/c/d", "auth a/b/c/d", "go back", "help"';
    
    if (widget.mainRole == 'admin') {
      commands += ', "authenticate admin"';
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
                                  Expanded( // ADD EXPANDED TO PREVENT TEXT OVERFLOW
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
                                      overflow: TextOverflow.ellipsis, // ADD OVERFLOW HANDLING
                                      maxLines: 2, // LIMIT TO 2 LINES
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
                'Enter your admin credentials to continue',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              SizedBox(height: 30),
              Container(
                width: double.infinity,
                child: TextField(
                  controller: _uniqueIdController,
                  obscureText: true,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Admin Unique ID',
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),
              ),
              SizedBox(height: 20),
              // FIX THE BUTTON HERE - ADD CONSTRAINTS TO PREVENT OVERFLOW
              Container(
                width: double.infinity, // Ensure full width
                constraints: BoxConstraints(
                  minHeight: 50, // Ensure minimum height
                ),
                child: ElevatedButton(
                  onPressed: _authenticateAdmin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: EdgeInsets.symmetric(vertical: 14, horizontal: 16), // Adjusted padding
                  ),
                  child: _isLoading 
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.onPrimary),
                          ),
                        )
                      : Text(
                          'Authenticate as Admin', 
                          style: TextStyle(fontSize: 16),
                          textAlign: TextAlign.center, // Add text alignment
                          overflow: TextOverflow.ellipsis, // Prevent text overflow
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
          _showAuthenticationBottomSheet(hostel);
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
          ],
        ),
      ),
    );
  }

  void _showAuthenticationBottomSheet(String hostel) {
    _lastSelectedHostel = hostel;
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
                    'Authentication Required',
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
      // Clear the controller when bottom sheet is closed
      bottomSheetController.clear();
    });
  }

  void _authenticateAdmin() {
    if (_uniqueIdController.text.isEmpty) {
      _showStatusMessage('Please enter admin unique ID', isError: true);
      return;
    }
    _authenticateSubrole('ALL');
  }

  Future<void> _authenticateSubrole(String hostel) async {
    if (_uniqueIdController.text.isEmpty) {
      _showStatusMessage('Please enter unique ID', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
      _isSuccess = false;
      _isError = false;
      _statusMessage = 'Authenticating...';
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
          'unique_id': _uniqueIdController.text,
        }),
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['authenticated'] == true) {
          await prefs.setString('access_token', data['access_token']);
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
        _showStatusMessage('Authentication failed. Please check your unique ID.', isError: true);
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
      });
      _uniqueIdController.clear();
    }
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
    }

    if (widget.mainRole == 'canteen') {
      descriptions['view menu'] = 'Open weekly food menu';
      descriptions['show menu'] = 'Open weekly food menu';
      descriptions['food menu'] = 'Open weekly food menu';
    }

    return descriptions;
  }
}
