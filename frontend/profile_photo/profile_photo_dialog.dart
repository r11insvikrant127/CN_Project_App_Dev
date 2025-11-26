import 'package:flutter/material.dart';
import 'dart:io';
import 'profile_photo_service.dart';

class ProfilePhotoDialog extends StatelessWidget {
  final VoidCallback? onPhotoUpdated;
  final String userRole; // Add role parameter

  const ProfilePhotoDialog({
    Key? key, 
    this.onPhotoUpdated,
    required this.userRole, // Make role required
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.85,
        padding: EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with role info
            Text(
              'Profile Photo - ${userRole.toUpperCase()}',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'This photo is only for your role',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            SizedBox(height: 12),
            
            // Current Photo Preview
            _buildCurrentPhotoPreview(context),
            SizedBox(height: 24),
            
            // Action Buttons
            _buildActionButtons(context),
            SizedBox(height: 16),
            
            // Remove Photo Option
            _buildRemoveOption(context),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentPhotoPreview(BuildContext context) {
    return FutureBuilder<Widget>(
      future: ProfilePhotoService().getProfilePhotoWidget(
        role: userRole, // Pass the role
        size: 100,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              shape: BoxShape.circle,
            ),
            child: Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return snapshot.data ?? Container();
      },
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        // Gallery Button
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue[600]!, Colors.blue[400]!],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextButton.icon(
            onPressed: () => _handleImageSelection(context, true),
            icon: Icon(Icons.photo_library, color: Colors.white),
            label: Text(
              'Choose from Gallery',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: 15, horizontal: 20),
            ),
          ),
        ),
        SizedBox(height: 12),
        
        // Camera Button
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green[600]!, Colors.green[400]!],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextButton.icon(
            onPressed: () => _handleImageSelection(context, false),
            icon: Icon(Icons.camera_alt, color: Colors.white),
            label: Text(
              'Take Photo',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: 15, horizontal: 20),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRemoveOption(BuildContext context) {
    return FutureBuilder<String?>(
      future: ProfilePhotoService().getProfilePhotoPath(userRole), // Pass the role
      builder: (context, snapshot) {
        final hasPhoto = snapshot.data != null;
        
        if (!hasPhoto) return SizedBox();
        
        return OutlinedButton(
          onPressed: () => _handleRemovePhoto(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red,
            side: BorderSide(color: Colors.red),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text('Remove Current Photo'),
        );
      },
    );
  }

  Future<void> _handleImageSelection(BuildContext context, bool fromGallery) async {
    try {
      Navigator.of(context).pop(); // Close the dialog first
      
      final File? imageFile = fromGallery
          ? await ProfilePhotoService().pickImageFromGallery()
          : await ProfilePhotoService().takePhotoWithCamera();
      
      if (imageFile != null) {
        final String? savedPath = await ProfilePhotoService().saveImageToAppDirectory(imageFile, userRole); // Pass role
        
        if (savedPath != null) {
          await ProfilePhotoService().saveProfilePhotoPath(userRole, savedPath); // Pass role
          
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Profile photo updated successfully for ${userRole.toUpperCase()}!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
          
          // Notify parent about photo update
          if (onPhotoUpdated != null) {
            onPhotoUpdated!();
          }
        } else {
          _showErrorSnackBar(context, 'Failed to save profile photo');
        }
      }
    } catch (e) {
      _showErrorSnackBar(context, 'Error: ${e.toString()}');
    }
  }

  Future<void> _handleRemovePhoto(BuildContext context) async {
    try {
      Navigator.of(context).pop(); // Close the dialog first
      
      await ProfilePhotoService().deleteProfilePhoto(userRole); // Pass role
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Profile photo removed for ${userRole.toUpperCase()}!'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      
      // Notify parent about photo update
      if (onPhotoUpdated != null) {
        onPhotoUpdated!();
      }
    } catch (e) {
      _showErrorSnackBar(context, 'Error removing photo: ${e.toString()}');
    }
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
  }
}
