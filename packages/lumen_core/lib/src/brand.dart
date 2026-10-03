/// The single source of truth for user-facing brand strings.
///
/// "Lumen" is an internal codename (trademark conflict, see
/// docs/research/04-market.md). Renaming the product means changing this file
/// plus bundle ids; storage ids are deliberately decoupled from the brand.
class Brand {
  const Brand({
    required this.name,
    required this.tagline,
    required this.supportUrl,
    required this.storageId,
  });

  final String name;
  final String tagline;
  final String supportUrl;

  /// Stable on-disk identifier. Never changes on a public rename.
  final String storageId;
}

const kBrand = Brand(
  name: 'Lumen',
  tagline: 'Drop your photos in. AI edits them. Every edit stays a slider.',
  supportUrl: 'https://example.com/support',
  storageId: 'lumen_catalog_v1',
);
