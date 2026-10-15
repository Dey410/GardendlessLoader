import 'package:flutter/material.dart';

import '../../models.dart';
import '../launcher_actions.dart';
import 'garden_widgets.dart';

/// Announcement links plus the loader's own social links, without showing
/// the same site twice (announcement URLs may carry tracking queries).
List<AnnouncementLink> announcementLinks(Announcement? announcement) {
  final links = announcement?.links ?? const <AnnouncementLink>[];
  return <AnnouncementLink>[
    ...links,
    for (final link in socialLinks)
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
  final links = announcementLinks(announcement);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('announcement-dialog'),
      title: Text(announcement?.title ?? '公告'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: SelectableText(announcement?.message ?? '暂无公告。'),
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
          label: '关闭',
          compact: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}
