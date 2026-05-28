import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_profile.dart';
import '../repositories/fridge_repository.dart';
import '../repositories/user_repository.dart';
import 'fcm_service.dart';
import 'notification_settings_service.dart';

class AuthService {
  AuthService._();

  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// 현재 사용자
  static User? get currentUser => _auth.currentUser;

  /// 로그인 상태 변경
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// 현재 사용자 정보
  static Future<UserProfile?> currentProfile() async {
    final uid = currentUser?.uid;
    if (uid == null) return null;
    return UserRepository.instance.get(uid);
  }

  /// 회원가입
  static Future<String?> signUp({
    required String email,
    required String nickname,
    required String password,
    required String passwordConfirm,
  }) async {
    if (password != passwordConfirm) {
      return '입력하신 비밀번호 값이 다릅니다.';
    }

    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = cred.user;
      if (user == null) return '회원가입에 실패했습니다.';

      await UserRepository.instance.createOrUpdate(
        uid: user.uid,
        email: email,
        displayName: nickname,
      );

      await FridgeRepository.instance.create(
        ownerUid: user.uid,
        name: '$nickname의 냉장고',
      );

      // 가입 후 저장된 알림 설정에 따라 등록
      NotificationSettingsService.applyOnLogin();

      return null;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'email-already-in-use':
          return '이미 존재하는 이메일입니다.';
        case 'invalid-email':
          return '잘못된 이메일 형식입니다.';
        case 'weak-password':
          return '비밀번호는 6자 이상이어야 합니다.';
        default:
          return '회원가입 중 오류가 발생했습니다: ${e.code}';
      }
    } catch (e) {
      return '회원가입 중 오류가 발생했습니다.';
    }
  }

  /// 로그인
  static Future<bool> login({
    required String email,
    required String password,
    bool rememberLogin = true,
  }) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      // 로그인 후 저장된 알림 설정에 따라 등록
      NotificationSettingsService.applyOnLogin();
      return true;
    } on FirebaseAuthException {
      return false;
    }
  }

  /// 자동 로그인 확인
  static Future<bool> checkSavedLogin() async {
    return _auth.currentUser != null;
  }

  /// 로그아웃
  static Future<void> logout() async {
    // 알림 토큰 삭제
    try {
      await FcmService.unregisterForUser();
    } catch (_) {
      // 실패해도 로그아웃 진행
    }
    await _auth.signOut();
  }
}
