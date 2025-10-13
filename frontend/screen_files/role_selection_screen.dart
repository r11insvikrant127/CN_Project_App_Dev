//role_selection_screen.dart

// role_selection_screen.dart - WITH VOICE COMMANDS
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'subrole_authentication_screen.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'theme_toggle_widget.dart';
import 'app_themes.dart';
import 'voice_command_mixin.dart';

class RoleSelectionScreen extends StatefulWidget {
  final String authMethod; // 'fingerprint' or 'device'

  const RoleSelectionScreen({Key? key, required this.authMethod}) : super(key: key);

  @override
  _RoleSelectionScreenState createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> with VoiceCommandMixin {
  String _deviceId = '';
  Map<String, dynamic>? _deviceInfo;

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
  }

  Future<void> _loadDeviceInfo() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _deviceId = prefs.getString('device_id') ?? '';
      String? deviceInfoJson = prefs.getString('device_info');
      if (deviceInfoJson != null) {
        _deviceInfo = Map<String, dynamic>.from(json.decode(deviceInfoJson));
      }
    });
  }

  @override
  Map<String, VoidCallback> getVoiceCommands() {
    return {
      'open admin': () => _navigateToRole('admin'),
      'open superintendent': () => _navigateToRole('super'),
      'open canteen': () => _navigateToRole('canteen'),
      'open security': () => _navigateToRole('security'),
      'admin': () => _navigateToRole('admin'),
      'superintendent': () => _navigateToRole('super'),
      'canteen': () => _navigateToRole('canteen'),
      'security': () => _navigateToRole('security'),
      'logout': _logout,
      'help': _showVoiceHelpDialog,
      'go back': _logout,
    };
  }
  // Add this method:
  void _showVoiceHelpDialog() {
    showVoiceHelp();
  }
  
  void _logout() {
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  void _showVoiceHelp() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Available voice commands: "open admin", "open superintendent", "open canteen", "open security", "logout", "help"',
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    return buildVoiceCommandUI(
      Scaffold(
        backgroundColor: Theme.of(context).colorScheme.background,
        appBar: AppBar(
          title: Text(
            'Select Your Role',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
          backgroundColor: AppThemes.getRoleColor('super', context),
          elevation: 0,
          centerTitle: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
          ),
          actions: [
            ThemeToggleWidget(),
            buildVoiceCommandButton(),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            physics: BouncingScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome Header
                  _buildWelcomeHeader(isDark),
                  SizedBox(height: 20),
                  
                  // Authentication Status Card
                  _buildAuthStatusCard(isDark),
                  SizedBox(height: 28),
                  
                  // Roles Section Header
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Available Roles',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Choose your role to continue',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 20),
                  
                  // Roles Grid
                  Container(
                    height: MediaQuery.of(context).size.height * 0.5,
                    child: _buildRoleGrid(isDark),
                  ),
                  
                  // Footer Info
                  SizedBox(height: 20),
                  _buildFooterInfo(isDark),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeHeader(bool isDark) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Color(0xFF1E3A8A).withOpacity(0.3),
                  Color(0xFF1E40AF).withOpacity(0.2),
                ]
              : [
                  Color(0xFF3B82F6).withOpacity(0.15),
                  Color(0xFF60A5FA).withOpacity(0.08),
                ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  Color(0xFF10B981),
                  Color(0xFF059669),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withOpacity(0.3),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              Icons.verified_user_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome Back!',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'You are successfully authenticated',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          _buildHeaderTimeWidget(isDark),
        ],
      ),
    );
  }

  Widget _buildAuthStatusCard(bool isDark) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: Theme.of(context).dividerColor,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Color(0xFF10B981).withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.verified,
                  color: Color(0xFF10B981),
                  size: 18,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.authMethod == 'fingerprint' 
                    ? 'Biometric Authentication Successful' 
                    : 'Device Authentication Successful',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          if (widget.authMethod == 'device' && _deviceId.isNotEmpty) 
            _buildInfoRow(
              Icons.fingerprint,
              'Device ID',
              _deviceId,
              isDark,
              isMonospace: true,
            ),
          if (widget.authMethod == 'fingerprint')
            _buildInfoRow(
              Icons.security,
              'Authentication',
              'Biometric Verified',
              isDark,
            ),
          if (_deviceInfo != null && widget.authMethod == 'device') ...[
            if (_deviceInfo!['status'] != null)
              _buildInfoRow(
                Icons.circle,
                'Status',
                _deviceInfo!['status']?.toString().toUpperCase() ?? 'ACTIVE',
                isDark,
                iconColor: Color(0xFF10B981),
              ),
            if (_deviceInfo!['device_name'] != null)
              _buildInfoRow(
                Icons.device_hub,
                'Device',
                _deviceInfo!['device_name'],
                isDark,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, bool isDark, 
      {bool isMonospace = false, Color? iconColor}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: iconColor ?? (isDark ? Color(0xFF60A5FA) : Color(0xFF3B82F6)),
          ),
          SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
                fontFamily: isMonospace ? 'RobotoMono' : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleGrid(bool isDark) {
    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: 0.85,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        _buildRoleCard('Admin', Icons.admin_panel_settings_rounded, 'admin', 
            'Full system access and management', isDark),
        _buildRoleCard('Superintendent', Icons.supervisor_account_rounded, 'super', 
            'Hostel supervision and monitoring', isDark),
        _buildRoleCard('Canteen', Icons.restaurant_rounded, 'canteen', 
            'Food service and student verification', isDark),
        _buildRoleCard('Security', Icons.security_rounded, 'security', 
            'Student movement tracking', isDark),
      ],
    );
  }

  Widget _buildRoleCard(String title, IconData icon, String role, String description, bool isDark) {
    Color roleColor = AppThemes.getRoleColor(role, context);
    
    // Enhanced colors for better visibility
    Color cardBackground = Theme.of(context).colorScheme.surface;
    Color titleColor = Theme.of(context).colorScheme.onSurface;
    Color descriptionColor = Theme.of(context).colorScheme.onSurfaceVariant;
    
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: cardBackground,
          border: Border.all(
            color: Theme.of(context).dividerColor,
            width: 1.5,
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              roleColor.withOpacity(isDark ? 0.2 : 0.1),
              roleColor.withOpacity(isDark ? 0.1 : 0.05),
            ],
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              _navigateToRole(role);
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon Container
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: roleColor.withOpacity(0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: roleColor.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      icon,
                      size: 22,
                      color: roleColor,
                    ),
                  ),
                  SizedBox(height: 12),
                  
                  // Title
                  Container(
                    height: 20,
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: titleColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(height: 4),
                  
                  // Description
                  Container(
                    height: 32,
                    child: Text(
                      description,
                      style: TextStyle(
                        fontSize: 11,
                        color: descriptionColor,
                        height: 1.2,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(height: 8),
                  
                  // Arrow Indicator
                  Row(
                    children: [
                      Text(
                        'Select',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: roleColor,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 12,
                        color: roleColor,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooterInfo(bool isDark) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor,
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Each role provides different access levels and functionalities within the system',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderTimeWidget(bool isDark) {
    return StreamBuilder(
      stream: Stream.periodic(Duration(seconds: 1)),
      builder: (context, snapshot) {
        final now = DateTime.now();
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? Color(0xFF1E40AF).withOpacity(0.2) : Color(0xFF3B82F6).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Theme.of(context).dividerColor,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // LIVE Badge
              Container(
                padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isDark ? Color(0xFF10B981) : Color(0xFF059669),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 3,
                      height: 3,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: 3),
                    Text(
                      'LIVE',
                      style: TextStyle(
                        fontSize: 7,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 4),
              // Time
              Text(
                DateFormat('HH:mm').format(now),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                  fontFamily: 'RobotoMono',
                ),
              ),
              // Date
              Text(
                DateFormat('MMM d').format(now),
                style: TextStyle(
                  fontSize: 9,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _navigateToRole(String role) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            SubroleAuthenticationScreen(mainRole: role),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOut;
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          var offsetAnimation = animation.drive(tween);

          return SlideTransition(
            position: offsetAnimation,
            child: child,
          );
        },
        transitionDuration: Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Map<String, String> getVoiceCommandDescriptions() {
    return {
      'open admin': 'Navigate to Admin authentication',
      'open superintendent': 'Navigate to Superintendent authentication',
      'open canteen': 'Navigate to Canteen authentication',
      'open security': 'Navigate to Security authentication',
      'admin': 'Short command for Admin role',
      'superintendent': 'Short command for Superintendent role',
      'canteen': 'Short command for Canteen role',
      'security': 'Short command for Security role',
      'logout': 'Log out and return to login',
      'go back': 'Return to previous screen',
      'help': 'Show this help dialog',
      'dark': 'Switch to dark theme', // ADD THIS
      'dark theme': 'Switch to dark theme', // ADD THIS
      'light': 'Switch to light theme', // ADD THIS
      'light theme': 'Switch to light theme', // ADD THIS
      'switch theme': 'Toggle between dark and light themes', // ADD THIS
      'toggle theme': 'Toggle between dark and light themes', // ADD THIS
    };
  }
}
