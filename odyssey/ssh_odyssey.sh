#!/usr/bin/expect -f

set config_fd [open "~/.odyssey" "r"]
gets $config_fd odyssey_username
gets $config_fd odyssey_password
gets $config_fd odyssey_secret

spawn ssh $odyssey_username@odyssey

expect {
	"Password:" {
		sleep 1
		send "$odyssey_password\r"
		exp_continue
	} "Verification code:" {
		sleep 1
		set verification_code [exec oathtool --totp --base32 $odyssey_secret]
		send "$verification_code\r"
		exp_continue
	} "~]$ " {
		interact
	}
}
