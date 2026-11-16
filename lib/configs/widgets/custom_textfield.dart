import 'package:flutter/material.dart';
import 'package:laantech_pos_task/configs/res/text_styles.dart';
import 'package:laantech_pos_task/configs/res/sizedbox_spaccing.dart';

class CustomTextFormField extends StatelessWidget {
  final String titleText;
  final String placeholder;
  final TextEditingController controller;
  final FocusNode? focusCurrent;
  final FocusNode? focusNext;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;
  final TextInputType keyboardType;
  final bool obscureText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final Iterable<String>? autofillHints;

  const CustomTextFormField({
    super.key,
    required this.titleText,
    required this.placeholder,
    required this.controller,
    this.focusCurrent,
    this.focusNext,
    this.validator,
    this.onSubmitted,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.autofillHints,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titleText,
          style: AppTextStyles.textSize14(context, weight: FontWeight.w500),
        ),
        SizedboxSpaccing.height01(context),
        TextFormField(
          controller: controller,
          focusNode: focusCurrent,
          keyboardType: keyboardType,
          obscureText: obscureText,
          validator: validator,
          autofillHints: autofillHints,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          textInputAction: focusNext != null
              ? TextInputAction.next
              : TextInputAction.done,
          onFieldSubmitted: (value) => focusNext != null
              ? focusNext!.requestFocus()
              : onSubmitted?.call(value),
          decoration: InputDecoration(
            hintText: placeholder,
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
          ),
        ),
      ],
    );
  }
}
