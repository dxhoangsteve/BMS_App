class BluetoothData {
  final int id;
  final int length;
  final List<int> data;

  BluetoothData({
    required this.id,
    required this.length,
    required this.data,
  });

  factory BluetoothData.fromJson(Map<String, dynamic> json) {
    return BluetoothData(
      id: json['id'] as int,
      length: json['length'] as int,
      data: List<int>.from(json['data'] as List),
    );
  }

  @override
  String toString() {
    return 'ID: $id, Length: $length, Data: $data';
  }
} 