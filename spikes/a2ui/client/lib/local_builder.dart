// WP-S1 spike (throwaway). Q4: a local, raw spec-shaped message as the
// on-device path would build it (A2UI_CATALOG section 8): one createSurface
// carrying components AND dataModel, no a2ui_core types involved.
import 'spike_catalog.dart' show spikeCatalogId;

List<Map<String, Object?>> localCaptureSurface({
  String surfaceId = 'local_cap_1',
}) => [
  {
    'version': '1.0',
    'createSurface': {
      'surfaceId': surfaceId,
      'catalogId': spikeCatalogId,
      'components': [
        {
          'id': 'root',
          'component': 'Column',
          'children': ['heard', 'list'],
        },
        {
          'id': 'heard',
          'component': 'Text',
          'text': 'Heard on device: "Spent ten thousand dinars on lunch"',
          'variant': 'caption',
        },
        {
          'id': 'list',
          'component': 'EntryList',
          'drafts': {'@path': '/drafts'},
          'status': 'review',
          'title': 'Built on the phone',
        },
      ],
      'dataModel': {
        'drafts': [
          {
            'id': 'd1',
            'intent': 'expense',
            'amountMinor': 10000,
            'currency': 'IQD',
            'categoryId': 'dining',
            'who': 'me',
            'occurredOn': '2026-11-22',
            'title': 'Lunch with the kids',
            'missing': ['accountId'],
            'origin': 'decisions',
          },
        ],
      },
    },
  },
];
