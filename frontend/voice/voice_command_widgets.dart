// voice_command_widgets.dart
import 'package:flutter/material.dart';

class VoiceCommandOverlay extends StatefulWidget {
  final bool isListening;
  final String statusMessage;

  const VoiceCommandOverlay({
    Key? key,
    required this.isListening,
    required this.statusMessage,
  }) : super(key: key);

  @override
  _VoiceCommandOverlayState createState() => _VoiceCommandOverlayState();
}

class _VoiceCommandOverlayState extends State<VoiceCommandOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  late Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    
    _animation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut)
    );
    
    _colorAnimation = ColorTween(
      begin: Colors.red[400],
      end: Colors.red[600],
    ).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool showOverlay = widget.isListening || widget.statusMessage.isNotEmpty;
    
    if (!showOverlay) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: widget.isListening 
            ? _buildListeningOverlay()
            : _buildStatusOverlay(),
      ),
    );
  }

  Widget _buildListeningOverlay() {
    return Material(
      color: Colors.transparent,
      child: Container(
        key: const ValueKey('listening'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: Colors.grey[200]!,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: _colorAnimation.value,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _colorAnimation.value!.withOpacity(0.5),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.mic,
                    color: Colors.white,
                    size: 12,
                  ),
                );
              },
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Listening...',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Speak your command now',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'LIVE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.red[700],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusOverlay() {
    final bool isSuccess = widget.statusMessage.contains('executed');
    final bool isError = widget.statusMessage.contains('not recognized') || 
                         widget.statusMessage.contains('Error');
    
    return Material(
      color: Colors.transparent,
      child: Container(
        key: ValueKey(widget.statusMessage),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSuccess 
              ? Colors.green[50]
              : isError
                  ? Colors.orange[50]
                  : Colors.blue[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSuccess 
                ? Colors.green[200]!
                : isError
                    ? Colors.orange[200]!
                    : Colors.blue[200]!,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSuccess 
                  ? Icons.check_circle
                  : isError
                      ? Icons.warning_amber
                      : Icons.info_outline,
              color: isSuccess 
                  ? Colors.green
                  : isError
                      ? Colors.orange
                      : Colors.blue,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.statusMessage,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isSuccess 
                      ? Colors.green[800]
                      : isError
                          ? Colors.orange[800]
                          : Colors.blue[800],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
                    colors: [Colors.red[400]!, Colors.red[600]!],
                  )
                : LinearGradient(
                    colors: [Colors.blue[400]!, Colors.blue[600]!],
                  ),
            boxShadow: [
              if (widget.isListening)
                BoxShadow(
                  color: Colors.red.withOpacity(0.4),
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
