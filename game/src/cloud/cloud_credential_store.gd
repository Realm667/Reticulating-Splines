class_name CloudCredentialStore
extends RefCounted
## Device tokens belong in the platform credential store, never in preferences.

static func store(account: String, token: String) -> Dictionary:
	if OS.has_feature("android"):
		return CloudAndroidCredentials.store(account, token)
	return NativePlatform.cloud_credential("store", account, token)

static func load_token(account: String) -> Dictionary:
	if OS.has_feature("android"):
		return CloudAndroidCredentials.load_token(account)
	return NativePlatform.cloud_credential("load", account, "")

static func delete(account: String) -> Dictionary:
	if OS.has_feature("android"):
		return CloudAndroidCredentials.delete(account)
	return NativePlatform.cloud_credential("delete", account, "")
