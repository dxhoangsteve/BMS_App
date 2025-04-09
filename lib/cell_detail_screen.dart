import 'package:flutter/material.dart';

class CellDetailScreen extends StatelessWidget {
  final Map<String, dynamic> parsedData;

  const CellDetailScreen({Key? key, required this.parsedData})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chi tiết Cell'),
        backgroundColor: Colors.blueAccent,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (parsedData.containsKey('cellVoltages')) ...[
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Điện áp từng cell',
                          style: Theme.of(context).textTheme.titleLarge),
                      SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(
                          parsedData['cellVoltages'].length,
                          (index) => Chip(
                            label: Text(
                              'Cell ${index + 1}: ${parsedData['cellVoltages'][index].toStringAsFixed(3)} V',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            SizedBox(height: 16),
            if (parsedData.containsKey('cellResistances')) ...[
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Điện trở từng cell',
                          style: Theme.of(context).textTheme.titleLarge),
                      SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(
                          parsedData['cellResistances'].length,
                          (index) => Chip(
                            label: Text(
                              'Cell ${index + 1}: ${parsedData['cellResistances'][index].toStringAsFixed(3)} Ω',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
