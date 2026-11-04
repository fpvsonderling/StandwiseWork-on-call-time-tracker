import 'dart:async';

import 'package:standwise/core/auth/google_tokens.dart';
import 'package:standwise/core/errors.dart';
import 'package:standwise/data/repositories/auth_repository.dart';
import 'package:standwise/data/repositories/profile_repository.dart';
import 'package:standwise/domain/models.dart';

const testUser = AuthUser(
  uid: 'u1',
  email: 'anna@example.com',
  emailVerified: true,
  displayName: 'Anna Maria Kowalska',
);

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({AuthUser? signedIn, this.signInResult = testUser})
    : _user = signedIn;

  AuthUser? _user;
  final AuthUser signInResult;
  final _changes = StreamController<AuthUser?>.broadcast();
  AppException? nextSignInError;

  @override
  Stream<AuthUser?> authStateChanges() async* {
    yield _user;
    yield* _changes.stream;
  }

  @override
  AuthUser? get currentUser => _user;

  @override
  Future<AuthUser> signInWithGoogle({
    required BrowserRedirectMessages messages,
  }) async {
    final error = nextSignInError;
    if (error != null) {
      nextSignInError = null;
      throw error;
    }
    _user = signInResult;
    _changes.add(_user);
    return _user!;
  }

  @override
  Future<void> signOut() async {
    _user = null;
    _changes.add(null);
  }
}

class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository([Map<String, UserProfile>? profiles])
    : _profiles = {...?profiles};

  final Map<String, UserProfile> _profiles;
  final _changes = StreamController<void>.broadcast();
  final saved = <({String first, String last, bool exists})>[];

  @override
  Stream<UserProfile?> watchProfile(String uid) async* {
    yield _profiles[uid];
    await for (final _ in _changes.stream) {
      yield _profiles[uid];
    }
  }

  @override
  Future<void> saveName({
    required AuthUser user,
    required String firstName,
    required String lastName,
    required bool exists,
  }) async {
    saved.add((first: firstName, last: lastName, exists: exists));
    _profiles[user.uid] = UserProfile(
      uid: user.uid,
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      email: user.email,
    );
    _changes.add(null);
  }
}
