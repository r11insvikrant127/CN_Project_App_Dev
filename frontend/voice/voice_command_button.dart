// voice_command_button.dart
import 'package:flutter/material.dart';

class VoiceCommandButton extends StatefulWidget {
  final VoidCallback onPressed;
  final bool isListening;

  const VoiceCommandButton({
    Key? key,
    required this.onPressed,
    required this.isListening,
  }) : super(key: key);

  @override
  _VoiceCommandButtonState createState() => _VoiceCommandButtonState();
}

class _VoiceCommandButtonState extends State<VoiceCommandButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
  }

  @override
  void didUpdateWidget(VoiceCommandButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isListening) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: widget.isListening
                ? LinearGradient(
                    colors: [Colors.red.shade400, Colors.red.shade600],
                  )
                : LinearGradient(
                    colors: [Colors.blue.shade400, Colors.blue.shade600],
                  ),
            boxShadow: [
              if (widget.isListening)
                BoxShadow(
                  color: Colors.red.withOpacity(0.5),
                  blurRadius: 8 + (_controller.value * 8),
                  spreadRadius: _controller.value * 2,
                )
              else
                BoxShadow(
                  color: Colors.blue.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: IconButton(
            onPressed: widget.onPressed,
            icon: Icon(
              widget.isListening ? Icons.mic : Icons.mic_none,
              color: Colors.white,
            ),
            tooltip: 'Voice Commands',
          ),
        );
      },
    );
  }
}
