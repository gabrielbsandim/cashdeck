import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/features/pix_contacts/domain/pix_contact.dart';
import 'package:flutter/material.dart';

/// The contact's initials in a primary container circle.
class ContactAvatar extends StatelessWidget {
  const new({required this.contact, this.size = 40, super.key});

  final PixContact contact;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Text(
        contact.initials,
        style: AppTextStyles.labelLg.copyWith(
          color: palette.onPrimaryContainer,
        ),
      ),
    );
  }
}
