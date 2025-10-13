// theme_toggle_widget.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme_provider.dart';

class ThemeToggleWidget extends StatelessWidget {
  final bool showLabel;
  
  const ThemeToggleWidget({super.key, this.showLabel = false});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    
    return PopupMenuButton<ThemeMode>(
      icon: Icon(Icons.brightness_medium, color: Theme.of(context).appBarTheme.foregroundColor),
      tooltip: 'Change Theme',
      onSelected: (ThemeMode mode) {
        themeProvider.setTheme(mode);
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<ThemeMode>>[
        _buildThemeMenuItem(
          context,
          ThemeMode.system,
          Icons.settings_suggest,
          'System Default',
          'Follows device theme',
          themeProvider.themeMode == ThemeMode.system,
        ),
        _buildThemeMenuItem(
          context,
          ThemeMode.light,
          Icons.light_mode,
          'Light Theme',
          'Always use light mode',
          themeProvider.themeMode == ThemeMode.light,
        ),
        _buildThemeMenuItem(
          context,
          ThemeMode.dark,
          Icons.dark_mode,
          'Dark Theme',
          'Always use dark mode',
          themeProvider.themeMode == ThemeMode.dark,
        ),
      ],
    );
  }

  PopupMenuItem<ThemeMode> _buildThemeMenuItem(
    BuildContext context,
    ThemeMode mode,
    IconData icon,
    String title,
    String subtitle,
    bool isSelected,
  ) {
    return PopupMenuItem<ThemeMode>(
      value: mode,
      child: Container(
        constraints: BoxConstraints(minWidth: 200),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected 
                ? Theme.of(context).colorScheme.primary 
                : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              size: 24,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected 
                        ? Theme.of(context).colorScheme.primary 
                        : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

// Convenient widget for showing current theme status
class ThemeStatusWidget extends StatelessWidget {
  const ThemeStatusWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getThemeIcon(themeProvider.themeMode),
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          SizedBox(width: 6),
          Text(
            themeProvider.themeName,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getThemeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return Icons.light_mode;
      case ThemeMode.dark:
        return Icons.dark_mode;
      case ThemeMode.system:
        return Icons.settings_suggest;
    }
  }
}
