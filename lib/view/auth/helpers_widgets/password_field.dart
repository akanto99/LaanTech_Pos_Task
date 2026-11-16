import 'package:flutter/material.dart';
import 'package:laantech_pos_task/configs/widgets/custom_textfield.dart';

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.title,
    required this.controller,
    required this.validator,
    this.focusNode,
    this.focusNext,
    this.onSubmitted,
    this.autofillHints,
  });

  final String title;
  final TextEditingController controller;
  final String? Function(String?) validator;
  final FocusNode? focusNode;
  final FocusNode? focusNext;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return CustomTextFormField(
      titleText: widget.title,
      placeholder: '••••••',
      controller: widget.controller,
      focusCurrent: widget.focusNode,
      focusNext: widget.focusNext,
      validator: widget.validator,
      onSubmitted: widget.onSubmitted,
      obscureText: _obscure,
      autofillHints: widget.autofillHints,
      prefixIcon: const Icon(Icons.lock_outline),
      suffixIcon: IconButton(
        tooltip: _obscure ? 'Show password' : 'Hide password',
        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
        onPressed: () => setState(() => _obscure = !_obscure),
      ),
    );
  }
}
