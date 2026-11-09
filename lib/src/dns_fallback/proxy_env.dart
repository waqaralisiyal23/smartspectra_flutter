import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _SetEnvNative = Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef _SetEnv = int Function(Pointer<Utf8>, Pointer<Utf8>, int);
typedef _UnsetEnvNative = Int32 Function(Pointer<Utf8>);
typedef _UnsetEnv = int Function(Pointer<Utf8>);
typedef _GetEnvNative = Pointer<Utf8> Function(Pointer<Utf8>);

/// Sets and clears environment variables of this process (libc `setenv`),
/// which native code in the same process — the SDK's libcurl — reads.
/// `Platform.environment` is a snapshot and cannot be changed.
class ProcessEnv {
  ProcessEnv._();

  static final DynamicLibrary _libc = Platform.isAndroid
      ? DynamicLibrary.open('libc.so')
      : DynamicLibrary.process();

  static final _SetEnv _setenv = _libc.lookupFunction<_SetEnvNative, _SetEnv>(
    'setenv',
  );
  static final _UnsetEnv _unsetenv = _libc
      .lookupFunction<_UnsetEnvNative, _UnsetEnv>('unsetenv');
  static final _GetEnvNative _getenv = _libc
      .lookupFunction<_GetEnvNative, _GetEnvNative>('getenv');

  static void set(String name, String value) => using((arena) {
    _setenv(
      name.toNativeUtf8(allocator: arena),
      value.toNativeUtf8(allocator: arena),
      1,
    );
  });

  static void unset(String name) => using((arena) {
    _unsetenv(name.toNativeUtf8(allocator: arena));
  });

  /// The live value (unlike `Platform.environment`), or null.
  static String? get(String name) => using((arena) {
    final value = _getenv(name.toNativeUtf8(allocator: arena));
    return value == nullptr ? null : value.toDartString();
  });
}
