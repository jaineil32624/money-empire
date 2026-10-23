extends RefCounted
## Save files are signed so editing them by hand is detected (single-player anti-tamper).
## This is a deterrent, not real security — online play is protected server-side (see net.gd).

const SAVE_SALT := "money-empire::v1::integrity"


static func sign_data(data: String) -> String:
	return (data + SAVE_SALT).sha256_text()
