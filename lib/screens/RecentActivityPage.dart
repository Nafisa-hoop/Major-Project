import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class RecentActivityPage extends StatelessWidget {
  final String uid;
  const RecentActivityPage({Key? key, required this.uid}) : super(key: key);

  Future<List<Map<String, dynamic>>> getRecentExpenses(String uid) async {
    final groupsSnapshot = await FirebaseFirestore.instance
        .collection('groups')
        .where('members', arrayContains: uid)
        .get();

    List<Map<String, dynamic>> expenses = [];

    for (var groupDoc in groupsSnapshot.docs) {
      final groupName = groupDoc['name'] ?? "Unnamed Group";

      final expenseSnapshot =
      await groupDoc.reference.collection('expenses').get();

      for (var expDoc in expenseSnapshot.docs) {
        final data = expDoc.data();
        expenses.add({
          "description": data['description'] ?? "Expense",
          "amount": (data['amount'] ?? 0).toDouble(),
          "groupName": groupName,
          "timestamp": data['timestamp'],
        });
      }
    }

    // ✅ Sort by latest timestamp
    expenses.sort((a, b) {
      final tsA = (a['timestamp'] as Timestamp?)?.toDate() ?? DateTime(1970);
      final tsB = (b['timestamp'] as Timestamp?)?.toDate() ?? DateTime(1970);
      return tsB.compareTo(tsA); // latest first
    });

    return expenses;
  }

  Widget _activityCard({
    required String title,
    required double amount,
    required String groupName,
    DateTime? timestamp,
  }) {
    return Card(
      color: Colors.grey[900],
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: ListTile(
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        subtitle: Text(groupName,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("₹${amount.toStringAsFixed(2)}",
                style: const TextStyle(
                    color: Colors.amber, fontWeight: FontWeight.bold)),
            if (timestamp != null)
              Text(
                "${timestamp.day}/${timestamp.month}/${timestamp.year}",
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("All Recent Activity")),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: getRecentExpenses(uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: Colors.amber));
          }
          if (snapshot.hasError) {
            return const Center(
                child: Text("Error loading activity",
                    style: TextStyle(color: Colors.red)));
          }

          final expenses = snapshot.data ?? [];

          if (expenses.isEmpty) {
            return const Center(
                child: Text("No activity found",
                    style: TextStyle(color: Colors.white70)));
          }

          return ListView.builder(
            itemCount: expenses.length,
            itemBuilder: (context, index) {
              final exp = expenses[index];
              return _activityCard(
                title: exp['description'] ?? "Expense",
                amount: (exp['amount'] ?? 0).toDouble(),
                groupName: exp['groupName'] ?? "Group",
                timestamp: exp['timestamp'] != null
                    ? (exp['timestamp'] as Timestamp).toDate()
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}
