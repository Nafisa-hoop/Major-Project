import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String email; // Email from forgot password page
  final String verificationId;
  const OtpVerificationScreen({
    super.key,
    required this.email,
    required this.verificationId,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  String otp = '';
  bool isLoading = false;
  String errorMessage = '';

  Future<void> verifyCode() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      // Get OTP from Firestore for this email
      final snapshot = await FirebaseFirestore.instance
          .collection('emailOtps')
          .doc(widget.email)
          .get();

      if (!snapshot.exists) {
        setState(() {
          errorMessage = "No OTP found. Please resend.";
          isLoading = false;
        });
        return;
      }

      final storedOtp = snapshot.data()?['otp'];
      final expiry = snapshot.data()?['expiry']?.toDate();

      if (storedOtp == otp && expiry != null && expiry.isAfter(DateTime.now())) {
        // ✅ OTP is valid
        Navigator.pushReplacementNamed(context, '/resetPassword', arguments: widget.email);
      } else {
        setState(() {
          errorMessage = "Invalid or expired OTP.";
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = "Something went wrong. Try again.";
        isLoading = false;
      });
    }
  }

  Future<void> resendCode() async {
    try {
      setState(() {
        isLoading = true;
      });

      // Generate new OTP
      final newOtp = (1000 + (DateTime.now().millisecondsSinceEpoch % 9000)).toString();

      await FirebaseFirestore.instance
          .collection('emailOtps')
          .doc(widget.email)
          .set({
        'otp': newOtp,
        'expiry': DateTime.now().add(const Duration(minutes: 5)), // valid for 5 min
      });

      // TODO: Send OTP to email via Firebase Functions or your backend
      // Example: callCloudFunctionToSendEmail(widget.email, newOtp);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("New OTP sent to your email.")),
      );

      setState(() {
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                ),
                const Spacer(),
              ]),
              const SizedBox(height: 16),
              const Text(
                "Verification",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white),
              ),
              const SizedBox(height: 24),
              Text(
                "Enter the 4-digit code sent to ${widget.email}",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              PinCodeTextField(
                appContext: context,
                length: 4,
                keyboardType: TextInputType.number,
                animationType: AnimationType.fade,
                pinTheme: PinTheme(
                  shape: PinCodeFieldShape.box,
                  borderRadius: BorderRadius.circular(8),
                  fieldHeight: 50,
                  fieldWidth: 40,
                  inactiveColor: Colors.white24,
                  activeColor: Colors.yellow,
                  selectedColor: Colors.white,
                ),
                textStyle: const TextStyle(color: Colors.white),
                onChanged: (value) => otp = value,
              ),
              if (errorMessage.isNotEmpty)
                Text(errorMessage, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: isLoading ? null : verifyCode,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.yellow),
                child: isLoading
                    ? const CircularProgressIndicator(color: Colors.black)
                    : const Text("Verify", style: TextStyle(color: Colors.black)),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Didn't receive a code? ", style: TextStyle(color: Colors.white)),
                  GestureDetector(
                    onTap: resendCode,
                    child: const Text("Resend now", style: TextStyle(color: Colors.orangeAccent)),
                  )
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
