class_name CloudAndroidCredentials
extends RefCounted
## AES-GCM ciphertext in private preferences; keys stay in AndroidKeyStore.
## Any unavailable API or cryptographic failure returns an error, never plaintext.

static var _failed := false
static var _jni: Object


static func _call(object: Object, method: String, arguments := []) -> Variant:
	if _failed or object == null:
		_failed = true
		return null
	var result: Variant = object.callv(method, arguments)
	if _jni.get_exception() != null:
		_failed = true
		return null
	return result


static func _class(name: String) -> Object:
	return _call(_jni, "wrap", [name])


static func operate(action: String, account: String, token := "") -> Dictionary:
	var failure := {"ok": false, "error": "Secure credential storage is unavailable", "token": ""}
	if not OS.has_feature("android") or not Engine.has_singleton("JavaClassWrapper") or not Engine.has_singleton("AndroidRuntime"):
		return failure
	if account.is_empty() or account.length() > 256 or token.length() > 4096 or action not in ["store", "load", "delete"]:
		return failure
	_failed = false
	_jni = Engine.get_singleton("JavaClassWrapper")
	var alias := "ReticulatingSplines.Cloud." + account.sha256_text()
	var context: Object = _call(Engine.get_singleton("AndroidRuntime"), "getApplicationContext")
	var preferences: Object = _call(context, "getSharedPreferences", ["rs_cloud_credentials", 0])
	var store: Object = _call(_class("java.security.KeyStore"), "getInstance", ["AndroidKeyStore"])
	_call(store, "load", [null])
	if _failed:
		return failure
	if action == "delete":
		_call(store, "deleteEntry", [alias])
		var editor: Object = _call(preferences, "edit")
		_call(editor, "remove", [alias])
		var committed: Variant = _call(editor, "commit")
		return failure if _failed or not bool(committed) else {"ok": true, "token": "", "error": ""}
	var exists: Variant = _call(store, "containsAlias", [alias])
	if action == "store" and not bool(exists):
		var generator: Object = _call(_class("javax.crypto.KeyGenerator"), "getInstance", ["AES", "AndroidKeyStore"])
		var builder: Object = _call(_class("android.security.keystore.KeyGenParameterSpec$Builder"), "KeyGenParameterSpec$Builder", [alias, 3])
		_call(builder, "setBlockModes", [PackedStringArray(["GCM"])])
		_call(builder, "setEncryptionPaddings", [PackedStringArray(["NoPadding"])])
		_call(builder, "setKeySize", [256])
		_call(generator, "init", [_call(builder, "build")])
		_call(generator, "generateKey")
	if _failed:
		return failure
	var cipher: Object = _call(_class("javax.crypto.Cipher"), "getInstance", ["AES/GCM/NoPadding"])
	# JNI represents Java char[] as PackedByteArray. AndroidKeyStore accepts an
	# empty password; its key material is protected by the OS, not that array.
	var key: Object = _call(store, "getKey", [alias, PackedByteArray()])
	if key == null or _failed:
		return failure
	if action == "store":
		if token.is_empty():
			return failure
		_call(cipher, "init", [1, key])
		_call(cipher, "updateAAD", [account.to_utf8_buffer()])
		var ciphertext: Variant = _call(cipher, "doFinal", [token.to_utf8_buffer()])
		var iv: Variant = _call(cipher, "getIV")
		if _failed or not ciphertext is PackedByteArray or not iv is PackedByteArray:
			return failure
		var editor: Object = _call(preferences, "edit")
		_call(editor, "putString", [alias, JSON.stringify({"iv": Marshalls.raw_to_base64(iv), "data": Marshalls.raw_to_base64(ciphertext)})])
		var committed: Variant = _call(editor, "commit")
		return failure if _failed or not bool(committed) else {"ok": true, "token": "", "error": ""}
	var serialized: Variant = _call(preferences, "getString", [alias, ""])
	if _failed or not serialized is String or serialized.is_empty():
		return failure
	var data: Variant = JSON.parse_string(serialized)
	if not data is Dictionary or not data.get("iv") is String or not data.get("data") is String:
		return failure
	var iv := Marshalls.base64_to_raw(data.iv)
	if iv.size() != 12:
		return failure
	var parameters: Object = _call(_class("javax.crypto.spec.GCMParameterSpec"), "GCMParameterSpec", [128, iv])
	_call(cipher, "init", [2, key, parameters])
	_call(cipher, "updateAAD", [account.to_utf8_buffer()])
	var clear: Variant = _call(cipher, "doFinal", [Marshalls.base64_to_raw(data.data)])
	return failure if _failed or not clear is PackedByteArray else {"ok": true, "token": clear.get_string_from_utf8(), "error": ""}


static func store(account: String, token: String) -> Dictionary:
	return operate("store", account, token)


static func load_token(account: String) -> Dictionary:
	return operate("load", account)


static func delete(account: String) -> Dictionary:
	return operate("delete", account)
