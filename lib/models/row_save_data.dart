class RowSaveData {
  final int rowOrder;
  final List<bool> revealed;
  final int appeared;
  final int? success;
  final int? importance;

  const RowSaveData({
    required this.rowOrder,
    required this.revealed,
    this.success,
    this.appeared = 0,
    this.importance,
  });

  Map<String, dynamic> toJson() => {
    'rowOrder': rowOrder,
    'revealed': revealed,
    if (appeared > 0) 'appeared': appeared,
    if (success != null) 'success': success,
    if (importance != null) 'importance': importance,
  };

  factory RowSaveData.fromJson(Map<String, dynamic> json) {
    return RowSaveData(
      appeared: json['appeared'] is int && json['appeared'] >= 0
          ? json['appeared'] as int
          : 0,
      rowOrder: json['rowOrder'] is int ? json['rowOrder'] as int : 0,
      revealed: (json['revealed'] as List? ?? const [])
          .map((e) => e == true)
          .toList(),
      importance: (json['importance'] as int?)?.clamp(1, 10),
      success:
          ((json['success'] ?? json['difficulty']) is int
                  ? (json['success'] ?? json['difficulty']) as int
                  : null)
              ?.clamp(1, 10),
    );
  }
}
