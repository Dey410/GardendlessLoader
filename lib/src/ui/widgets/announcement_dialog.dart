import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../models.dart';
import '../launcher_actions.dart';
import 'garden_widgets.dart';

/// Announcement links plus the loader's own social links, without showing
/// the same site twice (announcement URLs may carry tracking queries).
List<AnnouncementLink> announcementLinks(
  Announcement? announcement,
  AppStrings strings,
) {
  final links = announcement?.links ?? const <AnnouncementLink>[];
  return <AnnouncementLink>[
    ...links,
    for (final link in socialLinks(strings))
      if (!links.any(
        (item) => Uri.tryParse(item.url)?.host == Uri.parse(link.url).host,
      ))
        link,
  ];
}

Future<void> showAnnouncementDialog(
  BuildContext context, {
  required Announcement? announcement,
  required Future<void> Function(String url) openUrl,
}) {
  final strings = context.strings;
  final links = announcementLinks(announcement, strings);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('announcement-dialog'),
      title: Text(announcement?.title ?? strings.announcement),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: SelectableText(
            announcement?.message ?? strings.noAnnouncement,
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      actions: [
        for (final link in links)
          GardenButton(
            label: link.label,
            leading: linkIcon(link),
            compact: true,
            tone: GardenButtonTone.ghost,
            onPressed: () => openUrl(link.url),
          ),
        GardenButton(
          label: strings.close,
          compact: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}
