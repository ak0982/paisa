import 'package:flutter/material.dart';
import '../../theme/paisa_colors.dart';
import '../../theme/paisa_theme.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/neo_surface.dart';
import 'profile_setup_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PaisaColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 30),
              child: Column(
                children: [
                  const SizedBox(height: 14),
                  NeoSticker(
                    size: 88,
                    radius: 24,
                    angle: -0.07,
                    color: PaisaColors.primary,
                    child: Container(
                      width: 62,
                      height: 62,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: PaisaColors.inkOnAccent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '₹',
                        style: PaisaTheme.sora(
                          size: 34,
                          weight: FontWeight.w800,
                          color: PaisaColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'My Paisa',
                    style: PaisaTheme.sora(
                      size: 30,
                      weight: FontWeight.w800,
                      color: PaisaColors.ink,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your money, on autopilot.',
                    style: PaisaTheme.manrope(
                      size: 15,
                      weight: FontWeight.w600,
                      color: PaisaColors.mutedCaption,
                    ),
                  ),
                  const SizedBox(height: 26),
                  const _DemoCard(),
                  const SizedBox(height: 22),
                  Text(
                    'Every bank SMS becomes a tracked transaction.\nNo typing. Ever.',
                    textAlign: TextAlign.center,
                    style: PaisaTheme.manrope(
                      size: 13,
                      color: PaisaColors.mutedCaption,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const _StepIndicator(activeIndex: 0),
                  const SizedBox(height: 16),
                  GradientButton(
                    label: 'GET STARTED →',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ProfileSetupScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DemoCard extends StatelessWidget {
  const _DemoCard();

  @override
  Widget build(BuildContext context) {
    return NeoSurface(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      radius: 18,
      borderWidth: 2,
      borderColor: PaisaColors.border,
      shadow: true,
      shadowOffset: 4,
      color: PaisaColors.cardElevated,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: PaisaColors.bankHdfc,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: const Text('💬', style: TextStyle(fontSize: 11)),
              ),
              const SizedBox(width: 8),
              Text(
                'HDFC Bank · SMS',
                style: PaisaTheme.manrope(
                  size: 11,
                  weight: FontWeight.w600,
                  color: PaisaColors.mutedCaption,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              style: PaisaTheme.manrope(
                size: 12.5,
                color: PaisaColors.ink,
              ),
              children: const [
                TextSpan(text: 'Sent Rs.486.00 from a/c ••4321 to '),
                TextSpan(
                  text: 'Swiggy',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: ' on 07-Jul UPI ref 5521.'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              Expanded(child: Divider(color: PaisaColors.border)),
              Icon(Icons.arrow_downward, size: 16, color: PaisaColors.primary),
              Expanded(child: Divider(color: PaisaColors.border)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: PaisaColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: PaisaColors.border, width: 1.5),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: PaisaColors.catFood,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: PaisaColors.inkOnAccent,
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Text('🍔', style: TextStyle(fontSize: 19)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Swiggy',
                        style: PaisaTheme.manrope(
                          size: 14,
                          weight: FontWeight.w700,
                          color: PaisaColors.ink,
                        ),
                      ),
                      Text(
                        '⚡ AUTO-ADDED · FOOD',
                        style: PaisaTheme.manrope(
                          size: 10,
                          weight: FontWeight.w700,
                          color: PaisaColors.primary,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '−₹486',
                  style: PaisaTheme.sora(
                    size: 15,
                    weight: FontWeight.w800,
                    color: PaisaColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
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
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final active = i == activeIndex;
        return Container(
          width: active ? 22 : 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 3.5),
          decoration: BoxDecoration(
            color: active ? PaisaColors.primary : PaisaColors.border,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}
