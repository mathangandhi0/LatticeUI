import os

def analyze():
    log_path = "build_log.txt"
    if not os.path.exists(log_path):
        print("Log file not found")
        return

    # Try different encodings
    encodings = ['utf-16', 'utf-8', 'ascii']
    content = ""
    for enc in encodings:
        try:
            with open(log_path, 'r', encoding=enc, errors='ignore') as f:
                content = f.read()
                if "Godot" in content or "Main:" in content:
                    print(f"Decoded with {enc}")
                    break
        except:
            continue
    
    if not content:
        print("Could not decode content or find relevant tags")
        return

    # Filter for relevant lines
    tags = ["GodotAppLoader", "Main:", "Icon:", "AppLoader:"]
    lines = content.splitlines()
    found = False
    for line in lines:
        if any(tag in line for tag in tags):
            # Remove zero bytes if any (sometimes happen in mixed encoding)
            clean_line = line.replace('\x00', '')
            if clean_line.strip():
                print(clean_line)
                found = True
    
    if not found:
        print("No relevant logs found in the file.")

if __name__ == "__main__":
    analyze()
