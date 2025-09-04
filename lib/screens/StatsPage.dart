import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  double totalPaid = 0;
  double totalOwed = 0;
  bool isLoading = true;
  double _getRoundedMaxY() {
    final maxVal = (totalPaid > totalOwed ? totalPaid : totalOwed);
    if (maxVal <= 100) return 100;
    if (maxVal <= 500) return 500;
    if (maxVal <= 1000) return 1000;
    if (maxVal <= 5000) return 5000;
    return ((maxVal ~/ 1000) + 1) * 1000; // round up to nearest 1000
  }

  double _getInterval() {
    final maxY = _getRoundedMaxY();
    return maxY / 5; // 5 clean steps
  }

  @override
  void initState() {
    super.initState();
    fetchUserStats();
  }

  Future<void> fetchUserStats() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    double paid = 0;
    double owed = 0;

    try {
      final groupSnapshot = await FirebaseFirestore.instance
          .collection('groups')
          .where('members', arrayContains: uid)
          .get();

      for (var groupDoc in groupSnapshot.docs) {
        final expensesSnapshot =
        await groupDoc.reference.collection('expenses').get();

        for (var expenseDoc in expensesSnapshot.docs) {
          final data = expenseDoc.data();

          if (data['paidBy'] == uid) {
            paid += (data['amount'] ?? 0).toDouble();
          }

          if (data['splits'] != null) {
            for (var split in List.from(data['splits'])) {
              if (split['memberId'] == uid) {
                owed += (split['owed'] ?? 0).toDouble();
              }
            }
          }
        }
      }

      setState(() {
        totalPaid = paid;
        totalOwed = owed;
        isLoading = false;
      });
    } catch (e) {
      print("Error fetching stats: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Stats"),
        centerTitle: true,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Summary cards
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildSummaryCard("Total Paid", totalPaid, Colors.green),
                _buildSummaryCard("Total Owed", totalOwed, Colors.red),
              ],
            ),
            const SizedBox(height: 24),

            // Chart
            Expanded(
              child: Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: _getRoundedMaxY(),
                        barTouchData: BarTouchData(enabled: true),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              interval: _getInterval(),
                              getTitlesWidget: (value, meta) {
                                if (value == 0) return const Text("0");
                                return Text(
                                  value.toInt().toString(),
                                  style: const TextStyle(fontSize: 12),
                                );
                              },
                            ),
                          ),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                switch (value.toInt()) {
                                  case 0:
                                    return const Text("Paid", style: TextStyle(fontWeight: FontWeight.bold));
                                  case 1:
                                    return const Text("Owed", style: TextStyle(fontWeight: FontWeight.bold));
                                }
                                return const Text("");
                              },
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        gridData: FlGridData(show: false),
                        barGroups: [
                          BarChartGroupData(x: 0, barRods: [
                            BarChartRodData(
                              toY: totalPaid,
                              gradient: const LinearGradient(
                                colors: [Colors.green, Colors.lightGreenAccent],
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                              ),
                              width: 40,
                              borderRadius: BorderRadius.circular(8),
                            )
                          ]),
                          BarChartGroupData(x: 1, barRods: [
                            BarChartRodData(
                              toY: totalOwed,
                              gradient: const LinearGradient(
                                colors: [Colors.red, Colors.orangeAccent],
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                              ),
                              width: 40,
                              borderRadius: BorderRadius.circular(8),
                            )
                          ]),
                        ],
                      )
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String title, double amount, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: color, fontSize: 16)),
            const SizedBox(height: 8),
            Text("₹${amount.toStringAsFixed(2)}",
                style:
                const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
