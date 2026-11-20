# 8q: personal data out of the collected logs (collect_logs.sh). Extended regex (sed -E). Technical values (versions,
# timestamps, pids, package names) must stay readable. Order matters: MAC addresses before "Connecting to".
s/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<email>/g
s/([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}/<mac>/g
s/\+[0-9][0-9 ]{7,16}[0-9]/<phone>/g
s/([Ii][Mm][Ee][Ii][^0-9]{0,6})[0-9]{14,16}/\1<imei>/g
# passwords and keys (OPPO network share logs Wi-Fi passwords in clear text)
s/(([Pp]ass[Ww]?(or)?[Dd]|[Pp]sk|PSK|preSharedKey|wepKeys?|pwd|[Ss]ecret)["']?[=:] ?)("([^"\\]|\\.)*"|'[^']*'|[^ ,;}"']+)/\1<redacted>/g
# Wi-Fi names: quoted JSON (also with escaped quotes), key=value, single quotes, URL-encoded id_str, wifi_<name> ids
s/(([Bb]?[Ss][Ss][Ii][Dd]|[Ww]ifi[Nn]ame|networkName|configKey)["']?[=:]? ?)("([^"\\]|\\.)*"|'[^']*'|[^ ,;}^"']+)/\1<ssid>/g
s/(id_str=)[^] ]*/\1<redacted>/g
s/(id=wifi_)[^},]*/\1<ssid>/g
s/(Connecting to )[^ ]+ (<mac>)/\1<ssid> \2/g
# accounts, people and device names
s/((accountName|account_name|userName|user_name|nickName|nickname|NickName|ssoid|ssoId|mobile|phoneNum|realName|displayName|deviceName|devName|device_name|hostName|"dn"|client)["']?[=:] ?)("([^"\\]|\\.)*"|[^,} ]*)/\1<redacted>/g
s/(Account \{name=)[^,}]*/\1<redacted>/g
# coordinates
s/((lat|latitude|lng|lon|longitude)["']?[=:] ?)-?[0-9]+\.[0-9]+/\1<loc>/g
