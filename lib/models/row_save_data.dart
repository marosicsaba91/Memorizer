class RowSaveData {
  final int rowOrder;
  final List<bool> revealed;
  final int difficulty;

  const RowSaveData({
    required this.rowOrder,
    required this.revealed,
    required this.difficulty,
  });

  Map<String, dynamic> toJson() => {
    'rowOrder': rowOrder,
    'revealed': revealed,
    'difficulty': difficulty,
  };

  factory RowSaveData.fromJson(Map<String, dynamic> json) {
    return RowSaveData(
      rowOrder: json['rowOrder'] is int ? json['rowOrder'] as int : 0,
      revealed: (json['revealed'] as List? ?? const [])
          .map((e) => e == true)
          .toList(),
      difficulty: (json['difficulty'] is int ? json['difficulty'] as int : 5)
          .clamp(1, 10),
    );
  }
}
