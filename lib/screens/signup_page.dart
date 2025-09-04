import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  String? fullName, username, email, phone, password;
  bool agreeToPolicy = false;
  bool isLoading = false;

  Future<void> _signup() async {
    try {
      setState(() => isLoading = true);

      // Firebase Auth - Create user
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email!,
        password: password!,
      );
      final uid = userCredential.user!.uid;

      // Firestore - Save user data
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'uid': uid,
        'fullName': fullName,
        'username': username,
        'email': email,
        'phone': phone,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Navigate to Home with username
      Navigator.pushReplacementNamed(
        context,
        '/home',
        arguments: {'username': username ?? 'User'},
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: ListView(
              children: [
                const Text(
                  "Sign up",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 8),
                const Text("Sign up and begin your journey", style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 24),

                _buildTextField("Full name", "Enter your full name",
                        (val) => val!.isEmpty ? 'Required' : null, (val) => fullName = val),
                const SizedBox(height: 12),

                _buildTextField("Username", "Enter your username",
                        (val) => val!.isEmpty ? 'Required' : null, (val) => username = val),
                const SizedBox(height: 12),

                _buildTextField("Email address", "Enter your email",
                        (val) => !val!.contains('@') ? 'Invalid email' : null, (val) => email = val),
                const SizedBox(height: 12),

                const Text("Phone", style: TextStyle(color: Colors.white)),
                IntlPhoneField(
                  decoration: InputDecoration(
                    hintText: 'Enter phone number',
                    hintStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Colors.white10,
                    border: const OutlineInputBorder(),
                  ),
                  style: const TextStyle(color: Colors.white),
                  dropdownTextStyle: const TextStyle(color: Colors.white),
                  initialCountryCode: 'IN',
                  onChanged: (phoneNumber) => phone = phoneNumber.completeNumber,
                ),

                const SizedBox(height: 12),
                _buildTextField("Password", "Min 6 characters",
                        (val) => val!.length < 6 ? 'Too short' : null, (val) => password = val,
                    obscure: true),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Checkbox(
                        value: agreeToPolicy,
                        onChanged: (val) => setState(() => agreeToPolicy = val!)),
                    const Text("I agree with ", style: TextStyle(color: Colors.amber)),
                    const Text("Terms and Privacy",
                        style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                  ],
                ),

                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () {
                    if (_formKey.currentState!.validate() && agreeToPolicy) {
                      _formKey.currentState!.save();
                      _signup();
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.yellow),
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.black)
                      : const Text("Sign up", style: TextStyle(color: Colors.black)),
                ),

                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Already have an account? ", style: TextStyle(color: Colors.amber)),
                    GestureDetector(
                      onTap: () => Navigator.pushNamed(context, '/login'),
                      child: const Text("Log in",
                          style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
      String label,
      String hint,
      String? Function(String?) validator,
      Function(String?) onSaved, {
        bool obscure = false,
      }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white)),
        const SizedBox(height: 6),
        TextFormField(
          obscureText: obscure,
          validator: validator,
          onSaved: onSaved,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white54),
            filled: true,
            fillColor: Colors.white10,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
          ),
        ),
      ],
    );
  }
}
