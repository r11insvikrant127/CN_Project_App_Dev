// voice_command_mixin.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'voice_command_service.dart';
import 'voice_command_widgets.dart';
import 'voice_command_help_dialog.dart';
import 'theme_provider.dart'; // Your existing theme provider

mixin VoiceCommandMixin<T extends StatefulWidget> on State<T> {
  final VoiceCommandService _voiceService = VoiceCommandService();
  bool _isListening = false;
  String _commandStatus = '';

  @override
  void initState() {
    super.initState();
    _initializeVoiceCommands();
  }

  @override
  void dispose() {
    _voiceService.unregisterCommands(runtimeType.toString());
    _voiceService.dispose();
    super.dispose();
  }

  // Initialize voice commands for the screen
  void _initializeVoiceCommands() {
    final commands = getVoiceCommands();
    
    // ADD BASE THEME COMMANDS TO ALL SCREENS
    final baseCommands = <String, VoidCallback>{
      'dark': () => switchToDarkTheme(),
      'dark theme': () => switchToDarkTheme(),
      'light': () => switchToLightTheme(),
      'light theme': () => switchToLightTheme(),
      'switch theme': toggleTheme,
      'toggle theme': toggleTheme,
      'help': _showVoiceHelpDialog,
    };
    
    // Merge base commands with screen-specific commands
    baseCommands.addAll(commands);
    
    _voiceService.registerCommands(runtimeType.toString(), baseCommands);
  }

  // Method to be implemented by screens to provide their commands
  Map<String, VoidCallback> getVoiceCommands() {
    return {}; // Default empty implementation
  }

  // Method to provide command descriptions for help dialog
  Map<String, String> getVoiceCommandDescriptions() {
    return {}; // Default empty implementation
  }

  // Start listening for voice commands
  Future<void> _startVoiceListening() async {
    await _voiceService.startListening(
      screenId: runtimeType.toString(),
      onCommandRecognized: (message) {
        setState(() {
          _commandStatus = message;
        });
        
        // Clear status message after 3 seconds
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _commandStatus = '';
            });
          }
        });
      },
      onListeningStateChanged: (listening) {
        setState(() {
          _isListening = listening;
        });
      },
    );
  }

  // Stop listening
  void _stopVoiceListening() {
    _voiceService.stopListening();
  }

  // Show voice command help dialog
  void _showVoiceHelpDialog() {
    final allCommands = <String, String>{
      // BASE THEME COMMANDS FOR ALL SCREENS
      'dark': 'Switch to dark theme',
      'dark theme': 'Switch to dark theme',
      'light': 'Switch to light theme',
      'light theme': 'Switch to light theme',
      'switch theme': 'Toggle between dark and light themes',
      'toggle theme': 'Toggle between dark and light themes',
      'help': 'Show this help dialog',
    };
    
    // Add screen-specific commands
    allCommands.addAll(getVoiceCommandDescriptions());
    
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => VoiceCommandHelpDialog(
        commands: allCommands,
        screenTitle: _getScreenTitle(),
      ),
    );
  }

  // Change theme method - USING YOUR EXISTING THEME PROVIDER
  void _changeTheme(bool isDark) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    
    // Use your theme provider's method (adjust based on your actual method names)
    if (isDark) {
      themeProvider.setTheme(ThemeMode.dark);
    } else {
      themeProvider.setTheme(ThemeMode.light);
    }
    
    setState(() {
      _commandStatus = isDark ? 'Switched to Dark Theme' : 'Switched to Light Theme';
    });
    
    // Clear status message after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _commandStatus = '';
        });
      }
    });
  }

  // Toggle theme method
  void _toggleTheme() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final isCurrentlyDark = themeProvider.themeMode == ThemeMode.dark;
    _changeTheme(!isCurrentlyDark);
  }

  String _getScreenTitle() {
    final type = runtimeType.toString();
    if (type.contains('RoleSelection')) return 'Role Selection';
    if (type.contains('SubroleAuthentication')) return 'Authentication';
    if (type.contains('StudentLookup')) return 'Student Lookup';
    return 'Current Screen';
  }

  // Build voice command UI elements
  Widget buildVoiceCommandUI(Widget child) {
    return Stack(
      children: [
        child,
        VoiceCommandOverlay(
          isListening: _isListening,
          statusMessage: _commandStatus,
        ),
      ],
    );
  }

  // Build voice command button for app bar
  Widget buildVoiceCommandButton() {
    return VoiceCommandButton(
      onPressed: _isListening ? _stopVoiceListening : _startVoiceListening,
      isListening: _isListening,
    );
  }

  bool get isVoiceListening => _isListening;
  String get commandStatus => _commandStatus;
  void showVoiceHelp() => _showVoiceHelpDialog();
  void switchToDarkTheme() => _changeTheme(true);
  void switchToLightTheme() => _changeTheme(false);
  void toggleTheme() => _toggleTheme();
}
