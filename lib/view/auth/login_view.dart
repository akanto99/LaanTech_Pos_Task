import 'package:flutter/material.dart';
import 'package:laantech_pos_task/configs/buttons/round_button.dart';
import 'package:laantech_pos_task/configs/res/color.dart';
import 'package:laantech_pos_task/configs/res/text_styles.dart';
import 'package:laantech_pos_task/configs/utils/routes/routes_name.dart';
import 'package:laantech_pos_task/configs/utils/utils.dart';
import 'package:laantech_pos_task/configs/validations/auth_validation.dart';
import 'package:laantech_pos_task/configs/widgets/custom_textfield.dart';
import 'package:laantech_pos_task/view/auth/auth_form_layout.dart';
import 'package:laantech_pos_task/view/auth/password_field.dart';
import 'package:laantech_pos_task/view_model/auth_view_model/auth_view_model.dart';
import 'package:provider/provider.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final error = await context.read<AuthViewModel>().login(
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
      title: 'Welcome back',
      subtitle: 'Sign in to manage your POS file transfers',
      form: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            children: [
              CustomTextFormField(
                titleText: 'Username',
                placeholder: 'Enter your username',
                controller: _usernameController,
                focusNext: _passwordFocus,
                validator: AuthValidation.username,
                autofillHints: const [AutofillHints.username],
                prefixIcon: const Icon(Icons.person_outline),
              ),
              const SizedBox(height: 16),
              PasswordField(
                title: 'Password',
                controller: _passwordController,
                focusNode: _passwordFocus,
                validator: AuthValidation.password,
                onSubmitted: (_) => _submit(),
                autofillHints: const [AutofillHints.password],
              ),
              const SizedBox(height: 24),
              Selector<AuthViewModel, bool>(
                selector: (_, vm) => vm.loading,
                builder: (_, loading, _) => RoundButton(
                  title: 'Sign In',
                  loading: loading,
                  iconData: Icons.login_rounded,
                  onPress: _submit,
                ),
              ),
            ],
          ),
        ),
      ),
      footer: TextButton(
        onPressed: () => Navigator.pushNamed(context, RoutesName.register),
        child: Text.rich(
          TextSpan(
            text: 'New here? ',
            style: AppTextStyles.textSize14(context),
            children: [
              TextSpan(
                text: 'Create an account',
                style: AppTextStyles.textSize14(
                  context,
                  weight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
