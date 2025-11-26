import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

class ProfilePhotoService {
  static final ProfilePhotoService _instance = ProfilePhotoService._internal();
  factory ProfilePhotoService() => _instance;
  ProfilePhotoService._internal();

  final ImagePicker _imagePicker = ImagePicker();
  
  // Add a stream controller to notify when profile photo changes
  final StreamController<String> _photoUpdateController = StreamController<String>.broadcast();

  // Get role-specific storage key
  String _getProfilePhotoKey(String role) {
    return 'user_profile_photo_${role.toLowerCase()}';
  }

  // Stream to listen for photo updates
  Stream<String> get onPhotoUpdated => _photoUpdateController.stream;

  // Notify listeners when photo is updated
  void _notifyPhotoUpdated(String role) {
    _photoUpdateController.add(role);
  }

  // Get profile photo path for specific role
  Future<String?> getProfilePhotoPath(String role) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_getProfilePhotoKey(role));
  }

  // Save profile photo path for specific role
  Future<void> saveProfilePhotoPath(String role, String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_getProfilePhotoKey(role), path);
    _notifyPhotoUpdated(role); // Notify listeners
  }

  // Pick image from gallery
  Future<File?> pickImageFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );
      
      if (image != null) {
        return File(image.path);
      }
    } catch (e) {
      print('Error picking image from gallery: $e');
    }
    return null;
  }

  // Take photo with camera
  Future<File?> takePhotoWithCamera() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );
      
      if (image != null) {
        return File(image.path);
      }
    } catch (e) {
      print('Error taking photo with camera: $e');
    }
    return null;
  }

  // Save image to app directory and return path
  Future<String?> saveImageToAppDirectory(File imageFile, String role) async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String fileName = 'profile_photo_${role.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final String newPath = '${appDir.path}/$fileName';
      
      // Copy the file to app directory
      await imageFile.copy(newPath);
      return newPath;
    } catch (e) {
      print('Error saving image to app directory: $e');
      return null;
    }
  }

  // Delete current profile photo for specific role
  Future<void> deleteProfilePhoto(String role) async {
    try {
      final String? currentPath = await getProfilePhotoPath(role);
      if (currentPath != null) {
        final File currentFile = File(currentPath);
        if (await currentFile.exists()) {
          await currentFile.delete();
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_getProfilePhotoKey(role));
      _notifyPhotoUpdated(role); // Notify listeners
    } catch (e) {
      print('Error deleting profile photo: $e');
    }
  }

  // Get profile photo as Widget for specific role with stream support
  Stream<Widget> getProfilePhotoWidgetStream({
    required String role,
    double size = 40,
    Color backgroundColor = Colors.grey,
  }) async* {
    // Yield initial photo
    yield await _getProfilePhotoWidget(role, size, backgroundColor);
    
    // Listen for updates and yield new photos when they occur
    await for (final updatedRole in _photoUpdateController.stream) {
      if (updatedRole == role) {
        yield await _getProfilePhotoWidget(role, size, backgroundColor);
      }
    }
  }

  // Helper method to get the actual widget
  Future<Widget> _getProfilePhotoWidget(String role, double size, Color backgroundColor) async {
    final String? photoPath = await getProfilePhotoPath(role);
    
    if (photoPath != null) {
      final File photoFile = File(photoPath);
      if (await photoFile.exists()) {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: ClipOval(
            child: Image.file(
              photoFile,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _buildDefaultAvatar(size, backgroundColor, role);
              },
            ),
          ),
        );
      }
    }
    
    return _buildDefaultAvatar(size, backgroundColor, role);
  }

  // Keep the existing method for backward compatibility
  Future<Widget> getProfilePhotoWidget({
    required String role,
    double size = 40,
    Color backgroundColor = Colors.grey,
  }) async {
    return _getProfilePhotoWidget(role, size, backgroundColor);
  }

  Widget _buildDefaultAvatar(double size, Color backgroundColor, String role) {
    // Different icons based on role for better visual distinction
    IconData icon;
    Color iconColor;
    
    switch (role.toLowerCase()) {
      case 'admin':
        icon = Icons.admin_panel_settings;
        iconColor = Colors.red;
        break;
      case 'super_a':
      case 'super_b':
      case 'super_c':
      case 'super_d':
        icon = Icons.supervisor_account;
        iconColor = Colors.orange;
        break;
      case 'security_a':
      case 'security_b':
      case 'security_c':
      case 'security_d':
        icon = Icons.security;
        iconColor = Colors.blue;
        break;
      case 'canteen_a':
      case 'canteen_b':
      case 'canteen_c':
      case 'canteen_d':
        icon = Icons.restaurant;
        iconColor = Colors.green;
        break;
      default:
        icon = Icons.person;
        iconColor = Colors.white;
    }
    
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Icon(
        icon,
        color: iconColor,
        size: size * 0.6,
      ),
    );
  }

  // Get all roles that have profile photos
  Future<List<String>> getRolesWithProfilePhotos() async {
    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys();
    final photoKeys = allKeys.where((key) => key.startsWith('user_profile_photo_')).toList();
    
    return photoKeys.map((key) => key.replaceFirst('user_profile_photo_', '')).toList();
  }

  // Dispose the stream controller when no longer needed
  void dispose() {
    _photoUpdateController.close();
  }
}
