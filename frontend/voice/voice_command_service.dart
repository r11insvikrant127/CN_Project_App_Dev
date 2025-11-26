// voice_command_service.dart
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter/material.dart';

class VoiceCommandService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  Function(String)? _onCommandRecognized;
  Function(bool)? _onListeningStateChanged;

  static final VoiceCommandService _instance = VoiceCommandService._internal();
  factory VoiceCommandService() => _instance;
  VoiceCommandService._internal();

  // Command mappings for different screens
  final Map<String, Map<String, VoidCallback>> _commandMap = {};

  // Initialize speech recognition
  Future<bool> initialize() async {
    bool available = await _speech.initialize(
      onStatus: (status) {
        debugPrint('Speech status: $status');
        if (status == 'done' && _isListening) {
          _stopListening();
        }
      },
      onError: (error) {
        debugPrint('Speech error: $error');
        _stopListening();
      },
    );
    return available;
  }

  // Register commands for a specific screen
  void registerCommands(String screenId, Map<String, VoidCallback> commands) {
    _commandMap[screenId] = commands;
  }

  // Unregister commands when leaving a screen
  void unregisterCommands(String screenId) {
    _commandMap.remove(screenId);
  }

  // Start listening for voice commands
  Future<void> startListening({
    required String screenId,
    required Function(String) onCommandRecognized,
    required Function(bool) onListeningStateChanged,
  }) async {
    if (_isListening) return;

    _onCommandRecognized = onCommandRecognized;
    _onListeningStateChanged = onListeningStateChanged;

    bool available = await initialize();
    if (!available) {
      _onCommandRecognized?.call('Speech recognition not available');
      return;
    }

    setState(() {
      _isListening = true;
    });

    await _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          _processSpeechResult(result.recognizedWords, screenId);
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      localeId: 'en_US',
      cancelOnError: true,
      listenMode: stt.ListenMode.confirmation,
    );
  }

  // Stop listening
  void stopListening() {
    if (_isListening) {
      _stopListening();
    }
  }

  void _stopListening() {
    _speech.stop();
    setState(() {
      _isListening = false;
    });
  }

  void setState(void Function() fn) {
    fn();
    _onListeningStateChanged?.call(_isListening);
  }

  // Process recognized speech and execute matching command
  void _processSpeechResult(String recognizedText, String screenId) {
    debugPrint('🎯 Recognized: "$recognizedText"');
    
    final commands = _commandMap[screenId];
    if (commands == null) {
      _onCommandRecognized?.call('No commands registered for this screen');
      return;
    }

    // Use the new matching method
    final matchedCommand = _findBestCommandMatch(recognizedText, commands);

    if (matchedCommand != null) {
      // Execute the command
      commands[matchedCommand]!();
      _onCommandRecognized?.call('Command executed: $matchedCommand');
    } else {
      debugPrint('❌ No command matched for: "$recognizedText"');
      debugPrint('📋 Available commands: ${commands.keys.toList()}');
      _onCommandRecognized?.call('Command not recognized: "$recognizedText"');
    }

    _stopListening();
  }

  // Enhanced command matching with better logic
  String? _findBestCommandMatch(String recognizedText, Map<String, VoidCallback> commands) {
    final normalizedText = recognizedText.toLowerCase().trim();
    final commandList = commands.keys.toList();
    
    debugPrint('🔍 Searching for best match for: "$normalizedText"');
    
    // First, try exact match
    for (final command in commandList) {
      if (normalizedText == command.toLowerCase()) {
        debugPrint('✅ Exact match found: "$command"');
        return command;
      }
    }
    
    // Then try contains match
    for (final command in commandList) {
      if (normalizedText.contains(command.toLowerCase())) {
        debugPrint('✅ Contains match found: "$command"');
        return command;
      }
    }
    
    // For authentication commands, try word-based matching
    if (normalizedText.contains('authenticate') || normalizedText.contains('auth')) {
      if (normalizedText.contains(' b ') || 
          normalizedText.contains('bee') || 
          normalizedText.contains('be') ||
          normalizedText.endsWith(' b') ||
          normalizedText.contains('two')) {
        debugPrint('✅ Authentication B detected');
        return _findCommandVariation(commands, 'b');
      } else if (normalizedText.contains(' c ') || 
                 normalizedText.contains('see') || 
                 normalizedText.contains('cee') ||
                 normalizedText.endsWith(' c') ||
                 normalizedText.contains('three')) {
        debugPrint('✅ Authentication C detected');
        return _findCommandVariation(commands, 'c');
      } else if (normalizedText.contains(' d ') || 
                 normalizedText.contains('dee') || 
                 normalizedText.endsWith(' d') ||
                 normalizedText.contains('four')) {
        debugPrint('✅ Authentication D detected');
        return _findCommandVariation(commands, 'd');
      } else if (normalizedText.contains(' a ') || 
                 normalizedText.contains('eh') || 
                 normalizedText.endsWith(' a') ||
                 normalizedText.contains('one')) {
        debugPrint('✅ Authentication A detected');
        return _findCommandVariation(commands, 'a');
      }
    }
    
    // For hostel commands - ENHANCED WITH NEW COMMANDS
    if (normalizedText.contains('hostel') || 
        normalizedText.contains('open') || 
        normalizedText.contains('select') ||
        normalizedText.contains('authenticate') ||
        normalizedText.contains('auth')) {
      if (normalizedText.contains(' b ') || normalizedText.contains('bee') || normalizedText.endsWith(' b') || normalizedText.contains('two')) {
        return _findCommandVariation(commands, 'b');
      } else if (normalizedText.contains(' c ') || normalizedText.contains('see') || normalizedText.endsWith(' c') || normalizedText.contains('three')) {
        return _findCommandVariation(commands, 'c');
      } else if (normalizedText.contains(' d ') || normalizedText.endsWith(' d') || normalizedText.contains('four')) {
        return _findCommandVariation(commands, 'd');
      } else if (normalizedText.contains(' a ') || normalizedText.endsWith(' a') || normalizedText.contains('one')) {
        return _findCommandVariation(commands, 'a');
      }
    }
    
    // NEW: Generic authentication command matching
    if (normalizedText.contains('authenticate') || normalizedText.contains('auth') || 
        normalizedText.contains('submit') || normalizedText.contains('confirm')) {
      // Try to find any authentication command
      for (final command in commandList) {
        if (command.contains('authenticate') || command.contains('auth')) {
          return command;
        }
      }
    }
    
    // NEW: Security action matching
    if (normalizedText.contains('student') || normalizedText.contains('check')) {
      if (normalizedText.contains('out') || normalizedText.contains('exit')) {
        return _findSecurityAction(commands, 'out');
      } else if (normalizedText.contains('in') || normalizedText.contains('enter')) {
        return _findSecurityAction(commands, 'in');
      }
    }
    
    // NEW: Time management matching for admin
    if (normalizedText.contains('time') || normalizedText.contains('limit')) {
      if (normalizedText.contains('manage') || normalizedText.contains('set') || normalizedText.contains('edit')) {
        return _findTimeManagementCommand(commands);
      }
    }
    
    // NEW: Report viewing matching
    if (normalizedText.contains('report') || normalizedText.contains('view report')) {
      return _findReportCommand(commands);
    }
    
    return null;
  }

  // Helper method to find command variations
  String? _findCommandVariation(Map<String, VoidCallback> commands, String letter) {
    final variations = [
      'authenticate $letter',
      'auth $letter',
      'authenticate hostel $letter',
      'hostel $letter',
      'open $letter',
      'select $letter'
    ];
    
    for (final variation in variations) {
      if (commands.containsKey(variation)) {
        return variation;
      }
    }
    return null;
  }

  // NEW: Helper method to find security actions
  String? _findSecurityAction(Map<String, VoidCallback> commands, String action) {
    final variations = [
      'check $action',
      'student $action'
    ];
    
    for (final variation in variations) {
      if (commands.containsKey(variation)) {
        return variation;
      }
    }
    return null;
  }

  // NEW: Helper method to find time management commands
  String? _findTimeManagementCommand(Map<String, VoidCallback> commands) {
    final variations = [
      'manage time',
      'set allowed time',
      'edit time limit'
    ];
    
    for (final variation in variations) {
      if (commands.containsKey(variation)) {
        return variation;
      }
    }
    return null;
  }

  // NEW: Helper method to find report commands
  String? _findReportCommand(Map<String, VoidCallback> commands) {
    final variations = [
      'weekly report',
      'view report'
    ];
    
    for (final variation in variations) {
      if (commands.containsKey(variation)) {
        return variation;
      }
    }
    return null;
  }

  bool get isListening => _isListening;
  void dispose() {
    _stopListening();
    _onCommandRecognized = null;
    _onListeningStateChanged = null;
  }
}
