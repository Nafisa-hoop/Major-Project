import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:rxdart/rxdart.dart';

class AllGroupsDuePage extends StatefulWidget {
  final String uid; // current user id
  const AllGroupsDuePage({Key? key, required this.uid}) : super(key: key);

  @override
  State<AllGroupsDuePage> createState() => _AllGroupsDuePageState();
}

class _AllGroupsDuePageState extends State<AllGroupsDuePage> {
  late Razorpay _razorpay;
  String? _currentPayee;
  double? _currentAmount;
  String? _currentGroupId;

  final Map<String, String> _userNameCache = {}; // cache for memberId → name

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  void _startPayment(String groupId, String payeeId, double amount) {
    _currentGroupId = groupId;
    _currentPayee = payeeId;
    _currentAmount = amount;

    var options = {
      'key': 'rzp_test_YourActualKeyHere',   // ⚠️ Replace with your real test key
      'amount': (amount * 100).round(),      // amount in paise (₹500 → 50000)
      'currency': 'INR',                     // ✅ always specify
      'name': 'Group Expense Split',
      'description': 'Pay dues in group $groupId',
      'prefill': {
        'contact': '9876543210',             // ⚠️ ideally get from user profile
        'email': 'test@example.com',
      },
      'timeout': 120, // ⏱️ 2 min session timeout
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      debugPrint("❌ Razorpay open error: $e");
    }
  }



  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    // same logic as before …
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    debugPrint("❌ ERROR: ${response.message}");
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    debugPrint("EXTERNAL_WALLET: ${response.walletName}");
  }

  /// 🔹 Per-Member Net Summary (only "I owe")
  /// 🔹 Per-Member Net Summary (only "I owe")
  Stream<Map<String, Map<String, dynamic>>> watchPerMemberSummary(String uid) async* {
    final groupsSnapshot = await FirebaseFirestore.instance
        .collection('groups')
        .where('members', arrayContains: uid)
        .get();

    final List<Stream<QuerySnapshot>> expenseStreams =
    groupsSnapshot.docs.map((groupDoc) {
      return groupDoc.reference.collection('expenses').snapshots();
    }).toList();

    if (expenseStreams.isEmpty) {
      yield {};
      return;
    }

    yield* Rx.combineLatestList(expenseStreams).map((snapshotsList) {
      final Map<String, Map<String, dynamic>> memberBalances = {};

      for (var snapshot in snapshotsList) {
        for (var expDoc in snapshot.docs) {
          final data = expDoc.data() as Map<String, dynamic>;
          final List<dynamic> splits = data['splits'] ?? [];

          final mySplit = splits.firstWhere(
                (s) => s['memberId'] == uid,
            orElse: () => null,
          );
          if (mySplit == null) continue;

          final double myPaid = (mySplit['paid'] ?? 0).toDouble();
          final double myOwed = (mySplit['owed'] ?? 0).toDouble();

          final String groupId = expDoc.reference.parent.parent!.id; // ✅ groupId

          // ✅ CASE 1: I OWE (only if owed > paid)
          if (myOwed > myPaid) {
            final payerId = data['paidBy'];
            if (payerId == null || payerId == uid) continue;

            final payerSplit = splits.firstWhere(
                  (s) => s['memberId'] == payerId,
              orElse: () => null,
            );
            if (payerSplit == null) continue;

            final payerName = payerSplit['name'] ?? payerId;
            final amountDue = myOwed - myPaid;

            memberBalances.putIfAbsent(payerId, () => {
              "name": payerName,
              "balance": 0.0,
              "groupId": groupId,
            });

            memberBalances[payerId]!["balance"] =
                (memberBalances[payerId]!["balance"] as double) - amountDue;
          }

          // ✅ CASE 2: Others OWE ME (only if paid > owed)
          if (myPaid > myOwed) {
            for (var split in splits) {
              if (split['memberId'] == uid) continue;

              final memberId = split['memberId'];
              final memberName = split['name'] ?? memberId;
              final memberOwesMe = (split['owed'] ?? 0).toDouble();

              if (memberOwesMe == 0) continue;

              memberBalances.putIfAbsent(memberId, () => {
                "name": memberName,
                "balance": 0.0,
                "groupId": groupId,
              });

              memberBalances[memberId]!["balance"] =
                  (memberBalances[memberId]!["balance"] as double) +
                      memberOwesMe;
            }
          }
        }
      }

      // 🚫 Remove zero balances
      memberBalances.removeWhere((_, v) => (v["balance"] as double) == 0);

      return memberBalances;
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("People You Owe")),
      body: StreamBuilder<Map<String, Map<String, dynamic>>>(
        stream: watchPerMemberSummary(widget.uid),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final dues = snapshot.data!;
          // ✅ Keep only entries where YOU OWE (balance < 0)
          final filteredDues =
          dues.entries.where((e) => (e.value["balance"] as double) < 0).toList();

          if (filteredDues.isEmpty) {
            return const Center(
                child: Text("🎉 You don’t owe anyone!",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: filteredDues.length,
            itemBuilder: (context, index) {
              final entry = filteredDues[index];
              final memberId = entry.key;
              final memberName = entry.value["name"];
              final balance = entry.value["balance"] as double;
              final groupId = entry.value["groupId"] as String;
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 3,
                child: ListTile(
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  leading: CircleAvatar(
                    radius: 24,
                    child: Text(memberName[0].toUpperCase(),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(memberName,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    "You owe ₹${balance.abs().toStringAsFixed(2)}",
                    style: const TextStyle(fontSize: 14, color: Colors.redAccent),
                  ),
                  trailing: ElevatedButton.icon(
                    icon: const Icon(Icons.payment, size: 18),
                    label: const Text("Pay"),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      _startPayment(groupId, memberId, balance.abs());  // ✅ real groupId now
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
