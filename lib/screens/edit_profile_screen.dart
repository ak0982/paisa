import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_settings.dart';
import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';
import '../widgets/gradient_button.dart';

/// Lets the user update their locally-stored name and email at any time.
/// Reached from the dashboard avatar or the profile header card.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    await context.read<AppSettings>().setProfile(
          name: _nameController.text,
          email: _emailController.text,
        );
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Profile updated'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: PaisaColors.ink,
      ),
    );
    Navigator.of(context).pop();
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
                    const SizedBox(width: 12),
                    Text(
                      'Edit profile',
                      style: PaisaTheme.sora(
                        size: 20,
                        weight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Center(
                  child: Consumer<AppSettings>(
                    builder: (context, settings, _) => Transform.rotate(
                      angle: -0.05,
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: PaisaColors.primary,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: PaisaColors.inkOnAccent,
                            width: 2.5,
                          ),
                          boxShadow: PaisaColors.hardShadow(offset: 4),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          settings.initials,
                          style: PaisaTheme.sora(
                            size: 28,
                            weight: FontWeight.w800,
                            color: PaisaColors.inkOnAccent,
                          ),
                        ),
                      ),
                    ),
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
                  onFieldSubmitted: (_) => _save(),
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
                GradientButton(label: 'SAVE CHANGES', onPressed: _save),
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
