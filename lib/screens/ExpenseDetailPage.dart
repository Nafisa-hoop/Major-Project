import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ExpenseDetailPage extends StatelessWidget {
  final String groupId;
  final String expenseId;

  const ExpenseDetailPage({
    super.key,
    required this.groupId,
    required this.expenseId,
  });

  Future<String> _getMemberName(String uid) async {
    final doc = await FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .doc(uid)
        .get();

    if (doc.exists) {
      return doc.data()?['name'] ?? "Unknown";
    }
    return "Unknown";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        title: const Text("Expense Details"),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('groups')
            .doc(groupId)
            .collection('expenses')
            .doc(expenseId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: Colors.amber));
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(
              child: Text("Expense not found",
                  style: TextStyle(color: Colors.white70)),
            );
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;

          final title = data['title'] ?? '';
          final amount = data['amount'] ?? 0;
          final paidByUid = data['paidBy'] ?? 'Unknown';
          final splitEqually = data['splitEqually'] ?? true;
          final splits = data['splits'] as List<dynamic>? ?? [];

          return FutureBuilder<String>(
            future: _getMemberName(paidByUid),
            builder: (context, paidBySnapshot) {
              final paidByName = paidBySnapshot.data ?? "Unknown";

              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    const SizedBox(height: 12),
                    Text("Paid by: $paidByName",
                        style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 8),
                    Text("Amount: ₹$amount",
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber)),
                    const SizedBox(height: 8),
                    Text(
                      splitEqually ? "Split: Equally" : "Split: Custom",
                      style: const TextStyle(color: Colors.white54),
                    ),
                    const Divider(color: Colors.grey, height: 24),

                    // Splits (breakdown per member)
                    Expanded(
                      child: ListView.builder(
                        itemCount: splits.length,
                        itemBuilder: (context, index) {
                          final p = splits[index] as Map<String, dynamic>;
                          final name = p['name'] ?? 'Unknown';
                          final share = p['amount'] ?? 0;

                          // If member is NOT the one who paid, show due in red
                          final isPayer = name == paidByName;

                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              name,
                              style: const TextStyle(color: Colors.white),
                            ),
                            trailing: Text(
                              "₹$share",
                              style: TextStyle(
                                color: isPayer ? Colors.amber : Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
