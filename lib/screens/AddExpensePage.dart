import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AddExpensePage extends StatefulWidget {
  final String groupId;
  final String groupName;
  final DocumentSnapshot? existingExpense; // ✅ for editing

  const AddExpensePage({
    super.key,
    required this.groupId,
    required this.groupName,
    this.existingExpense,
  });

  @override
  State<AddExpensePage> createState() => _AddExpensePageState();
}

class _AddExpensePageState extends State<AddExpensePage> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  bool splitEqually = true;
  String? paidBy;
  List<Map<String, dynamic>> members = [];
  Map<String, double> customSplits = {};
  double totalPercentage = 0;

  @override
  void initState() {
    super.initState();
    _loadMembers();
    _loadExistingExpense(); // ✅ load expense if editing
  }

  Future<void> _loadMembers() async {
    final membersSnapshot = await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('members')
        .orderBy('addedAt', descending: false)
        .get();

    List<Map<String, dynamic>> loadedMembers = [];

    for (var doc in membersSnapshot.docs) {
      final data = doc.data();
      loadedMembers.add({
        'id': data['uid'] ?? doc.id,
        'name': data['name'] ?? data['email'] ?? 'User',
      });
    }

    setState(() {
      members = loadedMembers;
    });
  }

  void _loadExistingExpense() {
    if (widget.existingExpense != null) {
      final data = widget.existingExpense!.data() as Map<String, dynamic>;

      _titleController.text = data['title'] ?? '';
      _amountController.text = (data['amount'] ?? '').toString();
      paidBy = data['paidBy'];
      splitEqually = data['splitEqually'] ?? true;

      if (!splitEqually) {
        final splits = (data['splits'] as List<dynamic>? ?? []);
        for (var s in splits) {
          customSplits[s['memberId']] = (s['percentage'] ?? 0).toDouble();
        }
        totalPercentage =
            customSplits.values.fold(0, (a, b) => a + b.toDouble());
      }
      setState(() {});
    }
  }

  Future<void> _saveExpense() async {
    if (_titleController.text.trim().isEmpty ||
        _amountController.text.trim().isEmpty) return;

    if (members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No members in this group")),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final equalShare = amount / members.length;

    if (!splitEqually && totalPercentage != 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Total percentage must be 100%")),
      );
      return;
    }

    final splits = members.map((member) {
      final percentage = splitEqually
          ? (100 / members.length)
          : (customSplits[member['id']] ?? 0);

      final shareAmount = splitEqually ? equalShare : (percentage / 100) * amount;

      return {
        'memberId': member['id'],
        'name': member['name'],
        'percentage': percentage,
        'amount': shareAmount,
        'paid': member['id'] == paidBy ? amount : 0, // ✅ payer pays full
        'owed': shareAmount, // ✅ everyone owes their share
      };
    }).toList();

    final expenseData = {
      'title': _titleController.text.trim(),
      'amount': amount,
      'paidBy': paidBy,
      'splitEqually': splitEqually,
      'splits': splits,
      'timestamp': FieldValue.serverTimestamp(),
    };

    if (widget.existingExpense == null) {
      // ✅ Add new expense
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('expenses')
          .add(expenseData);
    } else {
      // ✅ Update existing expense
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('expenses')
          .doc(widget.existingExpense!.id)
          .update(expenseData);
    }

    if (!mounted) return;
    Navigator.pop(context);
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(
              "${widget.existingExpense == null ? "Add" : "Update"} Expense - ${widget.groupName}")),
      body: members.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: "Title"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Amount"),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: paidBy,
              decoration: const InputDecoration(labelText: "Paid by"),
              items: members.map((member) {
                return DropdownMenuItem<String>(
                  value: member['id'],
                  child: Text(member['name']),
                );
              }).toList(),
              onChanged: (value) => setState(() => paidBy = value),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text("Split Equally"),
              value: splitEqually,
              onChanged: (val) {
                setState(() {
                  splitEqually = val;
                  customSplits.clear();
                  totalPercentage = 0;
                });
              },
            ),
            if (!splitEqually) ...[
              const Text("Custom Split (%)"),
              Column(
                children: members.map((member) {
                  return Row(
                    children: [
                      Expanded(child: Text(member['name'])),
                      SizedBox(
                        width: 80,
                        child: TextFormField(
                          initialValue: customSplits[member['id']]
                              ?.toString() ??
                              "0",
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            setState(() {
                              final parsed = double.tryParse(val) ?? 0;
                              customSplits[member['id']] = parsed;
                              totalPercentage = customSplits.values
                                  .fold(0, (a, b) => a + b);
                            });
                          },
                        ),
                      ),
                      const Text("%"),
                    ],
                  );
                }).toList(),
              ),
              Text("Total: $totalPercentage%"),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saveExpense,
              child: Text(widget.existingExpense == null
                  ? "Save Expense"
                  : "Update Expense"),
            ),
          ],
        ),
      ),
    );
  }
}
