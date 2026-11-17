class RowSaveData {
  final int rowOrder;
  final List<bool> revealed;
  final int failedCount;
  final int almostCount;
  final int successCount;
  final int? importance;

  const RowSaveData({
    required this.rowOrder,
    required this.revealed,
    this.failedCount = 0,
    this.almostCount = 0,
    this.successCount = 0,
    this.importance,
  });

  int get appeared => failedCount + almostCount + successCount;
  bool get hasPersonalResults => importance != null || appeared > 0;

  // Retain the centered scale used by table colors and sorting.
  int get successRating => (5 + successCount - failedCount).clamp(1, 10);

  RowSaveData withImportance(int? value) => RowSaveData(
    rowOrder: rowOrder,
    revealed: revealed,
    importance: value,
    failedCount: failedCount,
    almostCount: almostCount,
    successCount: successCount,
  );

  Map<String, dynamic> toPersonalJson() => {
    'appearedCount': appeared,
    'failedCount': failedCount,
    'almostCount': almostCount,
    'successCount': successCount,
    if (importance != null) 'importance': importance,
  };

  Map<String, dynamic> toJson() => {
    'rowOrder': rowOrder,
    'revealed': revealed,
    ...toPersonalJson(),
  };

  factory RowSaveData.fromJson(Map<String, dynamic> json) {
    int count(String field) {
      final value = json[field];
      return value is int && value >= 0 ? value : 0;
    }

    return RowSaveData(
      rowOrder: json['rowOrder'] is int ? json['rowOrder'] as int : 0,
      revealed: (json['revealed'] as List? ?? const [])
          .map((value) => value == true)
          .toList(),
      importance: (json['importance'] as int?)?.clamp(0, 10),
      failedCount: count('failedCount'),
      almostCount: count('almostCount'),
      successCount: count('successCount'),
    );
  }
}
