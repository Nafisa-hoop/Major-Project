import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import 'package:http/http.dart' as http;

class ReceivablesPage extends StatelessWidget {
  final String uid;
  const ReceivablesPage({Key? key, required this.uid}) : super(key: key);

  // 🔔 Notify member via FCM REST API
  Future<void> notifyMember(
      BuildContext context, String memberId, String memberName, double amount) async {
    try {
      // Get FCM token of that member
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(memberId)
          .get();
      final token = userDoc.data()?['fcmToken'];

      if (token == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("⚠️ $memberName has no device registered")),
        );
        return;
      }

      // ⚠️ Store this safely in backend (Cloud Function / Node server)
      const String serverKey = "YOUR_FIREBASE_SERVER_KEY_HERE";

      final notificationBody = {
        "to": token,
        "notification": {
          "title": "Payment Reminder 💸",
          "body": "Hey $memberName, you owe ₹${amount.toStringAsFixed(2)}!",
        },
        "data": {
          "type": "payment_reminder",
          "amount": amount.toString(),
          "fromUser": uid,
        }
      };

      final response = await http.post(
        Uri.parse("https://fcm.googleapis.com/fcm/send"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "key=$serverKey",
        },
        body: jsonEncode(notificationBody),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("✅ Reminder sent to $memberName")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Failed: ${response.body}")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("⚠️ Error: $e")),
      );
    }
  }

  // 🔄 Stream balances in real time
  Stream<Map<String, Map<String, Map<String, dynamic>>>> watchMemberBalances(
      String uid) async* {
    final groupsSnapshot = await FirebaseFirestore.instance
        .collection('groups')
        .where('members', arrayContains: uid)
        .get();

    final expenseStreams = groupsSnapshot.docs
        .map((groupDoc) => groupDoc.reference.collection('expenses').snapshots())
        .toList();

    if (expenseStreams.isEmpty) {
      yield {
        "dues": <String, Map<String, dynamic>>{},
        "receivables": <String, Map<String, dynamic>>{}
      };
      return;
    }

    double _asDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    yield* Rx.combineLatestList(expenseStreams).map((snapshotsList) {
      final Map<String, Map<String, dynamic>> dues = {};
      final Map<String, Map<String, dynamic>> receivables = {};

      for (var snapshot in snapshotsList) {
        for (var expDoc in snapshot.docs) {
          final data = expDoc.data() as Map<String, dynamic>;
          final splits = (data['splits'] ?? []) as List<dynamic>;

          if (splits.isEmpty) continue;

          final mySplit = splits.cast<Map<String, dynamic>>()
              .where((s) => s['memberId'] == uid)
              .toList();

          if (mySplit.isEmpty) continue;

          final myData = mySplit.first;
          final myPaid = _asDouble(myData['paid']);
          final myOwed = _asDouble(myData['owed']);
          final myBalance = myPaid - myOwed;

          if (myBalance > 0) {
            // ✅ Others owe me
            for (var split in splits) {
              final member = split as Map<String, dynamic>;
              if (member['memberId'] == uid) continue;

              final memberId = member['memberId'];
              final memberName = member['name'] ?? memberId;
              final memberOwesMe = _asDouble(member['owed']);

              if (memberOwesMe == 0) continue;

              receivables.putIfAbsent(memberId, () => {
                "name": memberName,
                "balance": 0.0,
              });
              receivables[memberId]!["balance"] =
                  (receivables[memberId]!["balance"] as double) + memberOwesMe;
            }
          } else if (myBalance < 0) {
            // ✅ I owe someone
            final payerId = data['paidBy'];
            if (payerId == null || payerId == uid) continue;

            final payerSplit = splits.cast<Map<String, dynamic>>()
                .where((s) => s['memberId'] == payerId)
                .toList();
            if (payerSplit.isEmpty) continue;

            final payerName = payerSplit.first['name'] ?? payerId;

            dues.putIfAbsent(payerId, () => {
              "name": payerName,
              "balance": 0.0,
            });
            dues[payerId]!["balance"] =
                (dues[payerId]!["balance"] as double) + myBalance.abs();
          }
        }
      }

      // 🔹 Net off receivables and dues
      for (var id in dues.keys.toList()) {
        if (receivables.containsKey(id)) {
          final receivable = receivables[id]!["balance"] as double;
          final due = dues[id]!["balance"] as double;
          final net = receivable - due;

          if (net > 0) {
            receivables[id]!["balance"] = net;
            dues.remove(id); // no more dues for this user
          } else if (net < 0) {
            dues[id]!["balance"] = -net;
            receivables.remove(id); // no more receivable for this user
          } else {
            receivables.remove(id);
            dues.remove(id);
          }
        }
      }

      dues.removeWhere((_, v) => (v["balance"] as double) == 0);
      receivables.removeWhere((_, v) => (v["balance"] as double) == 0);

      return {
        "dues": dues,
        "receivables": receivables,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Receivables 💰")),
      body: StreamBuilder<Map<String, Map<String, Map<String, dynamic>>>>(
        stream: watchMemberBalances(uid),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final receivables = snapshot.data!["receivables"] ?? {};

          if (receivables.isEmpty) {
            return const Center(
              child: Text(
                "Nobody owes you right now 🙂",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(12),
            children: receivables.entries.map((entry) {
              final memberId = entry.key;
              final memberName = entry.value["name"];
              final amount = (entry.value["balance"] as double);

              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.green,
                    child: Text(
                      memberName[0].toUpperCase(),
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(
                    memberName,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    "Owes you ₹${amount.toStringAsFixed(2)}",
                    style: TextStyle(color: Colors.grey[700], fontSize: 15),
                  ),
                  trailing: ElevatedButton.icon(
                    onPressed: () =>
                        notifyMember(context, memberId, memberName, amount),
                    icon: const Icon(Icons.notifications_active, size: 18),
                    label: const Text("Notify"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
