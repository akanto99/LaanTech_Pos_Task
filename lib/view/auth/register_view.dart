import 'package:flutter/material.dart';
import 'package:laantech_pos_task/configs/buttons/round_button.dart';
import 'package:laantech_pos_task/configs/utils/routes/routes_name.dart';
import 'package:laantech_pos_task/configs/utils/utils.dart';
import 'package:laantech_pos_task/configs/validations/auth_validation.dart';
import 'package:laantech_pos_task/configs/widgets/custom_textfield.dart';
import 'package:laantech_pos_task/view/auth/auth_form_layout.dart';
import 'package:laantech_pos_task/view/auth/password_field.dart';
import 'package:laantech_pos_task/view_model/auth_view_model/auth_view_model.dart';
import 'package:provider/provider.dart';

class RegisterView extends StatefulWidget {
  const RegisterView({super.key});

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final error = await context.read<AuthViewModel>().register(
      _usernameController.text,
      _passwordController.text,
    );
    if (!mounted) return;
    if (error != null) return Utils.flushBarErrorMessage(error, context);
    Navigator.pushNamedAndRemoveUntil(context, RoutesName.home, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return AuthFormLayout(
      title: 'Create account',
      subtitle: 'Register to upload and download POS files',
      form: Form(
        key: _formKey,
        child: Column(
          children: [
            CustomTextFormField(
              titleText: 'Username',
              placeholder: 'Choose a username',
              controller: _usernameController,
              focusNext: _passwordFocus,
              validator: AuthValidation.username,
              autofillHints: const [AutofillHints.newUsername],
              prefixIcon: const Icon(Icons.person_outline),
            ),
            const SizedBox(height: 16),
            PasswordField(
              title: 'Password',
              controller: _passwordController,
              focusNode: _passwordFocus,
              focusNext: _confirmFocus,
              validator: AuthValidation.password,
              autofillHints: const [AutofillHints.newPassword],
            ),
            const SizedBox(height: 16),
            PasswordField(
              title: 'Confirm password',
              controller: _confirmController,
              focusNode: _confirmFocus,
              validator: (value) => AuthValidation.confirmPassword(
                value,
                _passwordController.text,
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            Selector<AuthViewModel, bool>(
              selector: (_, vm) => vm.loading,
              builder: (_, loading, _) => RoundButton(
                title: 'Create Account',
                loading: loading,
                iconData: Icons.person_add_alt_1_rounded,
                onPress: _submit,
              ),
            ),
          ],
        ),
      ),
      footer: TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Already have an account? Sign in'),
      ),
    );
  }
}
