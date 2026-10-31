extends SceneTree
## A disposable real platform entry, distinct from every profile credential.

func _initialize() -> void:
	var account := "test-" + Crypto.new().generate_random_bytes(24).hex_encode()
	var token := Crypto.new().generate_random_bytes(32).hex_encode()
	var stored := CloudCredentialStore.store(account, token)
	if not stored.ok:
		assert(OS.get_name() != "Windows", "Windows credential manager must accept a disposable device token")
		print("PASS credential storage fails closed when no protected store is available")
		quit()
		return
	var loaded := CloudCredentialStore.load_token(account)
	var removed := CloudCredentialStore.delete(account)
	assert(removed.ok)
	assert(loaded.ok and loaded.token == token)
	var missing := CloudCredentialStore.load_token(account)
	assert(not missing.ok or missing.token.is_empty())
	print("PASS protected device token round trip and deletion")
	quit()
