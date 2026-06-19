
import os

log_path = r"D:\Pro_Dump\PureLauncher_Backup_4.5\build_log.txt"
with open(log_path, 'rb') as f:
    content = f.read()

# Filter out null bytes and normalize to ASCII if possible
# The log seems to have a space between every character
text = content.decode('utf-16le', errors='ignore') if b'\x00' in content else content.decode('utf-8', errors='ignore')

# Even if not UTF-16, if it's UTF-8 with spaces:
if '  ' in text:
    # Try to collapse spaces if they are between every char
    # e.g. "G o d o t" -> "Godot"
    pass

output_path = r"D:\Pro_Dump\PureLauncher_Backup_4.5\clean_log.txt"
with open(output_path, 'w', encoding='utf-8') as f:
    f.write(text)

print(f"Cleaned log written to {output_path}")
