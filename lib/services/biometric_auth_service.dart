import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Servicio de "bloqueo local" con huella / Face ID.
///
/// IMPORTANTE: esto NO es un mecanismo de autenticación contra el backend.
/// La huella solo autoriza el acceso a un email/contraseña que el propio
/// usuario guardó en el almacenamiento cifrado del dispositivo (Keychain en
/// iOS, Keystore respaldado por AES en Android) tras un primer login manual
/// exitoso. Una vez la huella es validada por el sistema operativo, el
/// login real sigue haciéndose con esas credenciales de la forma normal
/// (usuario y contraseña), tal como ya lo hace AuthProvider.login().
class BiometricAuthService {
  BiometricAuthService._internal();
  static final BiometricAuthService _instance = BiometricAuthService._internal();
  factory BiometricAuthService() => _instance;

  final LocalAuthentication _localAuth = LocalAuthentication();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  static const _kEnabledKey = 'biometric_login_enabled';
  static const _kEmailKey = 'biometric_login_email';
  static const _kPasswordKey = 'biometric_login_password';

  /// Verifica que el dispositivo tenga hardware biométrico configurado
  /// (huella, Face ID, etc.) y que la app pueda usarlo.
  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      if (!canCheck || !isSupported) return false;

      final available = await _localAuth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Lanza el diálogo nativo de huella/Face ID.
  /// Devuelve true solo si el sistema operativo confirmó la identidad.
  Future<bool> authenticate({
    String reason = 'Confirma tu identidad para iniciar sesión',
  }) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// ¿El usuario ya activó el login con huella en este dispositivo?
  Future<bool> isBiometricLoginEnabled() async {
    final value = await _storage.read(key: _kEnabledKey);
    return value == 'true';
  }

  /// Guarda las credenciales cifradas y marca la huella como activada.
  /// Debe llamarse justo después de un login manual exitoso.
  Future<void> enableBiometricLogin(String email, String password) async {
    await _storage.write(key: _kEmailKey, value: email);
    await _storage.write(key: _kPasswordKey, value: password);
    await _storage.write(key: _kEnabledKey, value: 'true');
  }

  /// Recupera las credenciales guardadas. Devuelve null si no hay nada
  /// o si el usuario nunca activó la huella.
  Future<({String email, String password})?> getStoredCredentials() async {
    final enabled = await isBiometricLoginEnabled();
    if (!enabled) return null;

    final email = await _storage.read(key: _kEmailKey);
    final password = await _storage.read(key: _kPasswordKey);
    if (email == null || password == null) return null;

    return (email: email, password: password);
  }

  /// Borra las credenciales guardadas y desactiva la huella
  /// (por ejemplo, si el usuario cierra sesión o pulsa "olvidar huella").
  Future<void> disableBiometricLogin() async {
    await _storage.delete(key: _kEmailKey);
    await _storage.delete(key: _kPasswordKey);
    await _storage.write(key: _kEnabledKey, value: 'false');
  }
}