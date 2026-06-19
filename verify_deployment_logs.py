
import os

def check_logs(filepath):
    if not os.path.exists(filepath):
        print(f"File not found: {filepath}")
        return

    try:
        # Read as bytes to handle null bytes/encoding issues
        with open(filepath, 'rb') as f:
            content_bytes = f.read()
            
        # Try a few common encodings or just clean null bytes
        content = content_bytes.replace(b'\x00', b'').decode('utf-8', errors='ignore')
        
        markers = [
            "V4.65 INITIALIZED",
            "!!! MAIN STARTUP !!!",
            "PureLauncher V4.65 Started",
            "MAIN STARTUP",
            "V4.65"
        ]
        
        print("--- Log Verification Report ---")
        for marker in markers:
            if marker in content:
                print(f"[FOUND] {marker}")
            else:
                print(f"[MISSING] {marker}")
        
        # Also print last 10 lines of cleaned content to see context
        lines = [line.strip() for line in content.split('\n') if line.strip()]
        print("\n--- Last 10 Log Lines ---")
        for line in lines[-10:]:
            print(line)

    except Exception as e:
        print(f"Error reading log: {e}")

if __name__ == "__main__":
    check_logs("build_log.txt")
