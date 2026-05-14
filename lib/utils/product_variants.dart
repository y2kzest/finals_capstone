import 'dart:convert';

/// One seller-defined variant option (e.g. "Small (250g)" at ₱50).
class ProductVariant {
  final String name;

  /// null means this variant uses the product's base price.
  final double? price;

  const ProductVariant({required this.name, this.price});

  Map<String, dynamic> toJson() => {
    'name': name,
    if (price != null) 'price': price,
  };

  factory ProductVariant.fromJson(Map<String, dynamic> json) => ProductVariant(
    name: (json['name'] as String?) ?? '',
    price: (json['price'] as num?)?.toDouble(),
  );

  @override
  String toString() => name;
}

/// Parses the `variants` TEXT column.
/// Handles the new JSON-array format AND the legacy plain-text format
/// ("With rice / Without rice").
List<ProductVariant> parseVariants(String? raw) {
  if (raw == null || raw.trim().isEmpty) return [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(ProductVariant.fromJson)
          .where((v) => v.name.isNotEmpty)
          .toList();
    }
  } catch (_) {}
  // Legacy fallback: split on / , |
  return raw
      .split(RegExp(r'[/,|]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .map((s) => ProductVariant(name: s))
      .toList();
}

/// Serialises a list of variants to the JSON string stored in the DB column.
String encodeVariants(List<ProductVariant> variants) =>
    jsonEncode(variants.map((v) => v.toJson()).toList());
