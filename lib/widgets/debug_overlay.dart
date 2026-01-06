import 'package:flutter/material.dart';

/// Виджет для отображения информации о виджете при наведении/нажатии
/// Работает только в debug режиме
class DebugOverlay extends StatelessWidget {
  final Widget child;
  final String? widgetName;
  final Map<String, dynamic>? properties;

  const DebugOverlay({
    super.key,
    required this.child,
    this.widgetName,
    this.properties,
  });

  @override
  Widget build(BuildContext context) {
    if (!const bool.fromEnvironment('dart.vm.product')) {
      // Только в debug режиме
      return _DebugWrapper(
        widgetName: widgetName,
        properties: properties,
        child: child,
      );
    }
    return child;
  }
}

class _DebugWrapper extends StatefulWidget {
  final Widget child;
  final String? widgetName;
  final Map<String, dynamic>? properties;

  const _DebugWrapper({
    required this.child,
    this.widgetName,
    this.properties,
  });

  @override
  State<_DebugWrapper> createState() => _DebugWrapperState();
}

class _DebugWrapperState extends State<_DebugWrapper> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Stack(
          children: [
            widget.child,
            if (_isHovered || _isPressed)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _isPressed ? Colors.red : Colors.blue,
                      width: 2,
                    ),
                    color: (_isPressed ? Colors.red : Colors.blue)
                        .withOpacity(0.1),
                  ),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.widgetName != null)
                            Text(
                              widget.widgetName!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          if (widget.properties != null)
                            ...widget.properties!.entries.map((entry) {
                              return Text(
                                '${entry.key}: ${entry.value}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

