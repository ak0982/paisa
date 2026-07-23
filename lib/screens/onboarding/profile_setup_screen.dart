import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_settings.dart';
import '../../theme/paisa_colors.dart';
import '../../theme/paisa_theme.dart';
import '../../widgets/gradient_button.dart';
import 'sms_permission_screen.dart';

/// Collects a few basic on-device profile details (name + optional email)
/// right after the welcome screen. Nothing leaves the device.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final settings = context.read<AppSettings>();
    _nameController.text = settings.userName;
    _emailController.text = settings.userEmail;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) return;
    await context.read<AppSettings>().setProfile(
          name: _nameController.text,
          email: _emailController.text,
        );
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SmsPermissionScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PaisaColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 16, 26, 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        backgroundColor: PaisaColors.dividerAlt,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        fixedSize: const Size(40, 40),
                      ),
                      icon: const Icon(Icons.chevron_left, size: 20),
                    ),
                    const _StepIndicator(activeIndex: 1),
                    const SizedBox(width: 40),
                  ],
                ),
                const SizedBox(height: 26),
                Center(
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: PaisaColors.primary,
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: PaisaColors.inkOnAccent,
                        width: 2.5,
                      ),
                      boxShadow: PaisaColors.hardShadow(offset: 4),
                    ),
                    child: const Icon(
                      Icons.person_outline,
                      size: 42,
                      color: PaisaColors.inkOnAccent,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Tell us about you',
                  textAlign: TextAlign.center,
                  style: PaisaTheme.sora(
                    size: 23,
                    weight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'We use this only to personalise your app. It stays on your device.',
                  textAlign: TextAlign.center,
                  style: PaisaTheme.manrope(
                    size: 13.5,
                    color: PaisaColors.muted,
                  ),
                ),
                const SizedBox(height: 26),
                const _FieldLabel('Your name'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: _inputDecoration('e.g. Aarav Sharma'),
                  style: PaisaTheme.manrope(size: 15, weight: FontWeight.w600),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your name';
                    }
                    if (value.trim().length < 2) {
                      return 'Name looks too short';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),
                const _FieldLabel('Email (optional)'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  decoration: _inputDecoration('you@example.com'),
                  style: PaisaTheme.manrope(size: 15, weight: FontWeight.w600),
                  onFieldSubmitted: (_) => _continue(),
                  validator: (value) {
                    final v = value?.trim() ?? '';
                    if (v.isEmpty) return null;
                    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                    if (!emailRegex.hasMatch(v)) {
                      return 'Enter a valid email or leave it blank';
                    }
                    return null;
                  },
                ),
                const Spacer(),
                GradientButton(
                  label: 'CONTINUE →',
                  onPressed: _continue,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: PaisaTheme.manrope(size: 15, color: PaisaColors.mutedLight),
      filled: true,
      fillColor: PaisaColors.card,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: PaisaColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: PaisaColors.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: PaisaColors.overBudget),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: PaisaColors.overBudget, width: 1.6),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: PaisaTheme.manrope(
        size: 13,
        weight: FontWeight.w700,
        color: PaisaColors.ink,
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.activeIndex});

  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(3, (i) {
        final active = i == activeIndex;
        return Container(
          width: active ? 22 : 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 3.5),
          decoration: BoxDecoration(
            color: active ? PaisaColors.credit : PaisaColors.border,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}
