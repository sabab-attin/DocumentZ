import 'package:flutter/widgets.dart';

/// Keeps a modal's controller alive until its closing animation removes it.
class TextControllerOwner extends StatefulWidget {
  const TextControllerOwner({
    super.key,
    required this.controller,
    required this.child,
  });
  final TextEditingController controller;
  final Widget child;

  @override
  State<TextControllerOwner> createState() => _TextControllerOwnerState();
}

class _TextControllerOwnerState extends State<TextControllerOwner> {
  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
