import os
import subprocess
import requests
from collections import defaultdict

# --- הגדרות ---
TOPIC_ID = "437"
FORUM_URL = "https://otzaria.org/forum"

INCOMPATIBLE_FOLDER = "ספרים שאינם מותאמים לאוצריא"

def book_name(filepath):
    return os.path.splitext(os.path.basename(filepath))[0]

def folder_of(filepath):
    parts = filepath[len("ספרים/"):].split('/')
    return parts[-2] if len(parts) >= 2 else "תיקייה ראשית"

def is_incompatible(filepath):
    parts = filepath[len("ספרים/"):].split('/')
    return parts[0] == INCOMPATIBLE_FOLDER

def get_changed_books():
    before_sha = os.environ.get("BEFORE_SHA")
    after_sha = os.environ.get("AFTER_SHA")

    if not before_sha or not after_sha or before_sha == "0000000000000000000000000000000000000000":
        git_cmd = ["git", "diff", "--name-status", "-M90", "HEAD~1", "HEAD"]
    else:
        git_cmd = ["git", "diff", "--name-status", "-M90", before_sha, after_sha]

    try:
        output = subprocess.check_output(git_cmd, text=True, encoding="utf-8")
    except subprocess.CalledProcessError:
        try:
            output = subprocess.check_output(
                ["git", "diff", "--name-status", "-M90", "HEAD~1", "HEAD"],
                text=True, encoding="utf-8"
            )
        except subprocess.CalledProcessError:
            return None

    added = defaultdict(list)       # folder -> [(name, incompatible)]
    modified = defaultdict(list)
    deleted = defaultdict(list)
    moved = []                       # [(name, old_folder, new_folder, incompatible)]

    for line in output.strip().split('\n'):
        if not line:
            continue
        parts = line.split('\t')
        status = parts[0]

        # העברה/שינוי שם בין תיקיות
        if status.startswith('R') and len(parts) == 3:
            old_path, new_path = parts[1], parts[2]
            if not old_path.startswith("ספרים/") and not new_path.startswith("ספרים/"):
                continue
            old_folder = folder_of(old_path) if old_path.startswith("ספרים/") else "?"
            new_folder = folder_of(new_path) if new_path.startswith("ספרים/") else "?"
            name = book_name(new_path if new_path.startswith("ספרים/") else old_path)
            inc = is_incompatible(new_path) if new_path.startswith("ספרים/") else is_incompatible(old_path)
            if old_folder != new_folder:
                moved.append((name, old_folder, new_folder, inc))
            else:
                # שינוי שם בתוך אותה תיקייה — מחשיבים כ"עודכן"
                modified[new_folder].append((name, inc))
            continue

        if len(parts) < 2:
            continue
        filepath = parts[1]
        if not filepath.startswith("ספרים/"):
            continue

        folder = folder_of(filepath)
        name = book_name(filepath)
        inc = is_incompatible(filepath)

        if status.startswith('A'):
            added[folder].append((name, inc))
        elif status.startswith('M'):
            modified[folder].append((name, inc))
        elif status.startswith('D'):
            deleted[folder].append((name, inc))

    def format_book_list(books_dict):
        compatible = {f: [b for b, i in books if not i] for f, books in books_dict.items()}
        incompatible = {f: [b for b, i in books if i] for f, books in books_dict.items()}
        compatible   = {f: bs for f, bs in compatible.items() if bs}
        incompatible = {f: bs for f, bs in incompatible.items() if bs}

        lines = ""
        for label, group in [("(ספרים מותאמים לאוצריא)", compatible), ("(ספרים שאינם מותאמים לאוצריא)", incompatible)]:
            if not group:
                continue
            lines += f"**{label}**\n"
            for folder, books in sorted(group.items()):
                if folder == "תיקייה ראשית":
                    for b in books:
                        lines += f"- {b}\n"
                else:
                    lines += f"- {folder}:\n"
                    for b in sorted(books):
                        lines += f"  - {b}\n"
            lines += "\n"
        return lines

    def format_moved(moved_list):
        compatible   = [(n, o, nf) for n, o, nf, i in moved_list if not i]
        incompatible = [(n, o, nf) for n, o, nf, i in moved_list if i]
        lines = ""
        for label, group in [("(ספרים מותאמים לאוצריא)", compatible), ("(ספרים שאינם מותאמים לאוצריא)", incompatible)]:
            if not group:
                continue
            lines += f"**{label}**\n"
            for name, old_f, new_f in sorted(group):
                lines += f"- {name}: {old_f} ← {new_f}\n"
            lines += "\n"
        return lines

    msg = ""
    if added:
        msg += "### **נוסף למאגר**\n"
        msg += format_book_list(added)
    if moved:
        msg += "### **הועבר בין תיקיות**\n"
        msg += format_moved(moved)
    if modified:
        msg += "### **עודכן במאגר**\n"
        msg += format_book_list(modified)
    if deleted:
        msg += "### **הוסר מהמאגר**\n"
        msg += format_book_list(deleted)

    return msg.strip() if msg else "בוצעו עדכונים טכניים במאגר (לא נמצאו שינויים ישירים בספרים)."


def post_to_nodebb(message):
    username = os.environ.get("USER_NAME")
    password = os.environ.get("PASSWORD")

    if not username or not password:
        print("שגיאה: חסרים שם משתמש או סיסמה בסודות של גיטאב.")
        return

    session = requests.Session()
    session.headers.update({
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Accept': 'application/json'
    })

    try:
        print(f"1. מתחבר ל-{FORUM_URL} כדי למשוך CSRF Token...")
        config_res = session.get(f"{FORUM_URL}/api/config")
        if config_res.status_code != 200:
            print(f"שגיאה בגישה לשרת ({config_res.status_code})")
            return

        csrf_token = config_res.json().get('csrf_token')
        if not csrf_token:
            print("לא נמצא אסימון אבטחה!")
            return

        print("2. מבצע לוגין עם השם והסיסמה של הבוט...")
        session.headers.update({'x-csrf-token': csrf_token})
        login_res = session.post(f"{FORUM_URL}/login", data={
            'username': username,
            'password': password,
            '_csrf': csrf_token
        })

        if login_res.status_code != 200:
            print(f"שגיאת התחברות (סטטוס {login_res.status_code}).")
            return

        print(f"3. שולח את העדכון לנושא {TOPIC_ID}...")
        post_res = session.post(
            f"{FORUM_URL}/api/v3/topics/{TOPIC_ID}",
            json={"content": message}
        )

        if post_res.status_code == 200:
            print("ההודעה פורסמה בהצלחה בפורום אוצריא!")
        else:
            print(f"שגיאה בעת פרסום ההודעה (סטטוס {post_res.status_code}): {post_res.text}")

    except Exception as e:
        print(f"שגיאה בתקשורת עם שרת הפורום: {e}")


if __name__ == "__main__":
    repo = os.environ.get("GITHUB_REPOSITORY", "")

    changes_text = get_changed_books()

    if changes_text is None:
        print("לא הצלחתי לקבל רשימת שינויים - לא מפרסם פוסט.")
        exit(0)

    if "לא נמצאו שינויים ישירים בספרים" not in changes_text:
        final_post = (
            changes_text
            + '\n\n---\nניתן להוריד באמצעות התוסף "[הורדת מאגר גיטאב](https://otzaria.org/plugins/6a0081ae54ae49eaed8d6a73)"\n'
            + f'או מ-[עמוד ה-Releases](https://github.com/{repo}/releases/latest).\n\n'
            + '**פוסט זה נכתב ע"י בוט**'
        )
        post_to_nodebb(final_post)
    else:
        print("הריצה הסתיימה: לא זוהו שינויים בקבצי הספרים, לכן לא פורסם פוסט בפורום.")
