import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Result of a successful Google sign-in, carrying both the Firebase Auth
/// identity (uid) and the raw Google profile fields needed to populate or
/// match an /Accounts record.
class GoogleAuthResult {
  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;

  GoogleAuthResult({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
  });
}

class GoogleAuthService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );
  static final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  /// Runs the Google account picker, then exchanges the Google credential
  /// for a Firebase Auth identity. Returns null if the user cancels the
  /// picker. Throws on any other failure.
  static Future<GoogleAuthResult?> signIn() async {
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null; // user cancelled

    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential =
        await _firebaseAuth.signInWithCredential(credential);
    final firebaseUser = userCredential.user;
    if (firebaseUser == null) {
      throw Exception('Google sign-in failed: no Firebase user returned.');
    }

    return GoogleAuthResult(
      uid: firebaseUser.uid,
      email: (firebaseUser.email ?? googleUser.email).toLowerCase(),
      displayName: firebaseUser.displayName ?? googleUser.displayName ?? '',
      photoUrl: firebaseUser.photoURL ?? googleUser.photoUrl,
    );
  }

  /// Signs out of both Google and Firebase Auth. Safe to call even if the
  /// user isn't currently signed in via Google (e.g. they logged in with
  /// email/password).
  static Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    try {
      await _firebaseAuth.signOut();
    } catch (_) {}
  }
}
