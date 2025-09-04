import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'notification_service.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<Map<String, dynamic>> notifications = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchOwedExpenses();
  }

  Future<void> fetchOwedExpenses() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      List<Map<String, dynamic>> notifs = [];

      // Get all groups the user is part of
      final groupsSnapshot = await FirebaseFirestore.instance
          .collection('groups')
          .where('members', arrayContains: user.uid)
          .get();

      for (var groupDoc in groupsSnapshot.docs) {
        // Fetch expenses inside this group's expenses subcollection
        final expensesSnapshot = await groupDoc.reference
            .collection('expenses')
            .where('participants.${user.uid}.owed', isGreaterThan: 0)
            .get();

        for (var expenseDoc in expensesSnapshot.docs) {
          final data = expenseDoc.data();
          final owedAmount = data['participants'][user.uid]['owed'] ?? 0;
          final desc = data['description'] ?? "Expense";

          notifs.add({
            "title": "You owe money",
            "message": "You owe ₹$owedAmount for $desc",
            "time": DateTime.now().toString(),
          });

          // Fire local notification immediately
          NotificationService.showNotification(
            title: "Payment Reminder",
            body: "You owe ₹$owedAmount for $desc. Please pay soon.",
          );
        }
      }

      // Ensure at least 2 notifications are shown
      if (notifs.length < 2) {
        notifs.addAll([
          {
            "title": "Reminder",
            "message": "Don’t forget to check your pending balances!",
            "time": DateTime.now().toString(),
          },
          {
            "title": "Tip",
            "message": "Pay your friends on time to avoid confusion 😊",
            "time": DateTime.now().toString(),
          },
        ]);
      }

      setState(() {
        notifications = notifs;
        isLoading = false;
      });
    } catch (e) {
      print("Error fetching owed expenses: $e");
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Notifications", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
      ),
      body: isLoading
          ? const Center(
        child: CircularProgressIndicator(color: Colors.amber),
      )
          : notifications.isEmpty
          ? const Center(
        child: Text("No reminders",
            style: TextStyle(color: Colors.white70)),
      )
          : ListView.builder(
        itemCount: notifications.length,
        itemBuilder: (context, index) {
          final notif = notifications[index];
          return ListTile(
            leading: const Icon(Icons.notifications, color: Colors.amber),
            title: Text(notif["title"],
                style: const TextStyle(color: Colors.white)),
            subtitle: Text(notif["message"],
                style: const TextStyle(color: Colors.white70)),
            trailing: Text(
              notif["time"].toString().substring(0, 16),
              style: const TextStyle(color: Colors.white38),
            ),
          );
        },
      ),
    );
  }
}
