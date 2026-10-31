//! Cloud device tokens only. Never falls back to a plaintext preferences file.

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
const SERVICE: &str = "ReticulatingSplines.Cloud";

pub fn valid_account(account: &str) -> bool {
    !account.is_empty() && account.len() <= 256 && !account.chars().any(char::is_control)
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
fn entry(account: &str) -> Result<keyring::Entry, String> {
    if !valid_account(account) {
        return Err("Invalid credential account".into());
    }
    keyring::Entry::new(SERVICE, account).map_err(|_| "Secure credential storage is unavailable".into())
}

pub fn store(account: &str, token: &str) -> Result<(), String> {
    if !valid_account(account) || token.is_empty() || token.len() > 4096 || token.chars().any(char::is_control) {
        return Err("Invalid credential".into());
    }
    #[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
    return entry(account)?
        .set_password(token)
        .map_err(|_| "Secure credential storage is unavailable".into());
    #[cfg(not(any(target_os = "windows", target_os = "macos", target_os = "linux")))]
    Err("Secure credential storage is unavailable".into())
}

pub fn load(account: &str) -> Result<String, String> {
    #[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
    return match entry(account)?.get_password() {
        Ok(token) => Ok(token),
        Err(keyring::Error::NoEntry) => Ok(String::new()),
        Err(_) => Err("Secure credential storage is unavailable".into()),
    };
    #[cfg(not(any(target_os = "windows", target_os = "macos", target_os = "linux")))]
    {
        let _ = account;
        Err("Secure credential storage is unavailable".into())
    }
}

pub fn delete(account: &str) -> Result<(), String> {
    #[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
    return match entry(account)?.delete_credential() {
        Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
        Err(_) => Err("Secure credential storage is unavailable".into()),
    };
    #[cfg(not(any(target_os = "windows", target_os = "macos", target_os = "linux")))]
    {
        let _ = account;
        Err("Secure credential storage is unavailable".into())
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn reject_untrusted_identifiers_and_tokens_before_accessing_os_store() {
        assert!(!super::valid_account(""));
        assert!(!super::valid_account("account\n"));
        assert!(!super::valid_account(&"x".repeat(257)));
        assert!(super::valid_account("https://rs.realm667.com/account-42"));
        assert!(super::store("account", "").is_err());
        assert!(super::store("account", "token\n").is_err());
    }
}
