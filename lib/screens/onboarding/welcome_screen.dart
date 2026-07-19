import 'package:flutter/material.dart';
import '../../theme/paisa_colors.dart';
import '../../theme/paisa_theme.dart';
import '../../widgets/gradient_button.dart';
import 'profile_setup_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: PaisaColors.welcomeGradient),
        child: SafeArea(
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
                Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.25)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '₹',
                    style: PaisaTheme.sora(
                      size: 42,
                      weight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Paisa',
                  style: PaisaTheme.sora(
                    size: 30,
                    weight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your money, on autopilot.',
                  style: PaisaTheme.manrope(
                    size: 15,
                    weight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.82),
                  ),
                ),
                const SizedBox(height: 26),
                _DemoCard(),
                const SizedBox(height: 22),
                Text(
                  'Every bank SMS becomes a tracked transaction.\nNo typing. Ever.',
                  textAlign: TextAlign.center,
                  style: PaisaTheme.manrope(
                    size: 13,
                    color: Colors.white.withOpacity(0.78),
                  ),
                ),
                const SizedBox(height: 32),
                const _StepIndicator(activeIndex: 0),
                const SizedBox(height: 16),
                GradientButton(
                  label: 'Get Started',
                  isWhite: true,
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
      ),
    );
  }
}

class _DemoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.97),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 40,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F0E7),
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
                color: const Color(0xFF42524A),
              ),
              children: const [
                TextSpan(
                  text:
                      'Sent Rs.486.00 from a/c ••4321 to ',
                ),
                TextSpan(
                  text: 'Swiggy',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: ' on 07-Jul UPI ref 5521.'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(child: Divider(color: PaisaColors.navBorder)),
              const Icon(Icons.arrow_downward, size: 16, color: PaisaColors.credit),
              const Expanded(child: Divider(color: PaisaColors.navBorder)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F8F6),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEDE7),
                    borderRadius: BorderRadius.circular(12),
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
                        ),
                      ),
                      Text(
                        '⚡ Auto-added · Food',
                        style: PaisaTheme.manrope(
                          size: 10.5,
                          weight: FontWeight.w600,
                          color: PaisaColors.credit,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '−₹486',
                  style: PaisaTheme.sora(size: 15, weight: FontWeight.w700),
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
            color: active
                ? Colors.white
                : Colors.white.withOpacity(0.4),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}
