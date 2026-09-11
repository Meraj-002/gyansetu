/// An administrative block within a [District].
class Block {
  const Block({required this.id, required this.name, required this.districtId});

  factory Block.fromJson(Map<String, dynamic> json, String districtId) => Block(
        id: json['id'] as String,
        name: json['name'] as String,
        districtId: districtId,
      );

  final String id;
  final String name;

  /// The district this block belongs to. Carried on the block so a saved block
  /// can never be silently paired with the wrong district.
  final String districtId;

  @override
  bool operator ==(Object other) => other is Block && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => name;
}

/// A district, with the blocks that belong to it.
class District {
  const District({required this.id, required this.name, required this.blocks});

  factory District.fromJson(Map<String, dynamic> json) {
    final String id = json['id'] as String;
    return District(
      id: id,
      name: json['name'] as String,
      blocks: <Block>[
        for (final dynamic b in json['blocks'] as List<dynamic>)
          Block.fromJson(b as Map<String, dynamic>, id),
      ],
    );
  }

  final String id;
  final String name;
  final List<Block> blocks;

  Block? blockById(String? blockId) {
    if (blockId == null) return null;
    for (final Block b in blocks) {
      if (b.id == blockId) return b;
    }
    return null;
  }

  @override
  bool operator ==(Object other) => other is District && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => name;
}
