import 'package:flutter/material.dart';

class SidebarMenu extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const SidebarMenu({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {

    return Container(
      width: 210,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E3A5F), Color(0xFF0D2137)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Logo / App name ────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.trending_up, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'DemandCast',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      letterSpacing: 0.3,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const Divider(color: Color(0xFF2D4A6A), height: 1),
          const SizedBox(height: 12),

          // ── Menu items ─────────────────────────────────────
          _SidebarItem(
            icon: Icons.bar_chart_rounded,
            label: 'Demand Forecasting',
            isActive: currentIndex == 0 || currentIndex == 1, // Both Dashboard and Forecasting highlight the same menu item if desired, or we can just say index 0. Let's map 0=Dashboard, 1=Forecasting, 2=Settings
            onTap: () => onTap(0),
          ),
          _SidebarItem(
            icon: Icons.settings_outlined,
            label: 'Settings',
            isActive: currentIndex == 2,
            onTap: () => onTap(2),
          ),

          const Spacer(),

          // ── Footer ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            child: const Text(
              'v1.0.0 · On-Premises',
              style: TextStyle(color: Color(0xFF4A7BA7), fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF2563EB).withOpacity(0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isActive
              ? Border.all(color: const Color(0xFF2563EB).withOpacity(0.5))
              : null,
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 18,
                color: isActive ? const Color(0xFF60A5FA) : const Color(0xFF8BA5BE)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.white : const Color(0xFF8BA5BE),
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}