import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/security/permissions.dart';

/// One colour per role, used on avatars and badges everywhere.
Color roleColor(StaffRole role) => switch (role) {
  StaffRole.owner => const Color(0xFF6B4EFF),
  StaffRole.cashier => AppColors.accent,
  StaffRole.waiter => const Color(0xFFD9822B),
  StaffRole.kitchen => const Color(0xFFC0392B),
};

IconData roleIcon(StaffRole role) => switch (role) {
  StaffRole.owner => Icons.admin_panel_settings_outlined,
  StaffRole.cashier => Icons.point_of_sale_outlined,
  StaffRole.waiter => Icons.room_service_outlined,
  StaffRole.kitchen => Icons.soup_kitchen_outlined,
};

String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
}

/// A round avatar with the person's initials in their role colour.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.name, required this.role, this.radius = 24});
  final String name;
  final StaffRole role;
  final double radius;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundColor: roleColor(role),
    child: Text(
      initialsOf(name),
      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: radius * 0.75),
    ),
  );
}

/// Small coloured role label ("Admin", "Waiter"…).
class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.role});
  final StaffRole role;

  @override
  Widget build(BuildContext context) {
    final color = roleColor(role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
      child: Text(
        role.label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}
