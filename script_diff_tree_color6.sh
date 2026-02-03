#!/bin/bash
set -e

# --- РЕЖИМ РАБОТЫ СКРИПТА ---
MODE="diff" # Режим по умолчанию
if [ "$1" == "structure" ]; then
  MODE="structure"
  echo "Режим: Только структура проекта."
else
  echo "Режим: Полный отчет с diff."
fi

echo "[1/6] Создаём директорию для отчётов..."
mkdir -p report

# --- БЛОК, ЗАВИСИМЫЙ ОТ РЕЖИМА 'diff' ---
if [ "$MODE" == "diff" ]; then
  echo "[2/6] Определяем коммиты..."
  LAST_COMMIT=$(git rev-parse HEAD)
  PREV_COMMIT=$(git rev-list -n1 --before="5 hours ago" HEAD 2>/dev/null || git rev-parse HEAD^)
  if [ -z "$PREV_COMMIT" ] || [ "$PREV_COMMIT" = "$LAST_COMMIT" ]; then
    PREV_COMMIT=$(git rev-parse HEAD^)
  fi

  # Получаем даты коммитов
  LAST_COMMIT_DATE=$(git show -s --format="%cd" --date=iso $LAST_COMMIT)
  PREV_COMMIT_DATE=$(git show -s --format="%cd" --date=iso $PREV_COMMIT)

  echo " Последний коммит: $LAST_COMMIT ($LAST_COMMIT_DATE)"
  echo " Коммит сравнения: $PREV_COMMIT ($PREV_COMMIT_DATE)"
fi

echo "[2.5/6] Настраиваем Git для вывода путей в UTF-8..."
OLD_QUOTE=$(git config --get core.quotepath 2>/dev/null || echo "true")
git config core.quotepath false

# --- БЛОК, ЗАВИСИМЫЙ ОТ РЕЖИМА 'diff' ---
if [ "$MODE" == "diff" ]; then
  echo "[3/6] Генерируем diff и diff.html..."
  git diff $PREV_COMMIT $LAST_COMMIT > report/changes.diff

  # Проверяем, установлен ли diff2html, если нет - устанавливаем локально
  if ! npx -c 'command -v diff2html' >/dev/null 2>&1; then
      echo "Установка diff2html-cli (может занять некоторое время)..."
      npm install diff2html-cli --save-dev >/dev/null 2>&1
  fi
  
  # Генерируем HTML из diff
  NODE_OPTIONS=--max-old-space-size=4096 npx diff2html -i file -s side -F report/diff.html -- report/changes.diff

  echo "[4/6] Собираем статусы изменённых файлов..."
  declare -A FILE_STATUS
  
  while read -r status file; do
    if [ -z "$status" ] || [ -z "$file" ]; then continue; fi

    case "$status" in
      A) color="green";;
      M) color="orange";;
      D) color="red";;
      *) continue;;
    esac

    FILE_STATUS["$file"]="$color"
    path="$file"
    while [[ "$path" =~ / ]]; do
      path="${path%/*}"
      if [ -n "$path" ]; then
        if [ -z "${FILE_STATUS[$path]}" ] || [ "${FILE_STATUS[$path]}" = "green" ] || \
           [ "${FILE_STATUS[$path]}" = "orange" -a "$color" = "red" ]; then
          FILE_STATUS["$path"]="$color"
        fi
      else
        break
      fi
    done
  done < <(git diff --name-status "$PREV_COMMIT" "$LAST_COMMIT" | LC_ALL=C tr -d '\r')
fi

echo "[5/6] Генерируем report/final_report.html..."

# Начинаем HTML
cat > report/files.html << 'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<title>Git Report</title>
<style>
body { font-family: Arial, sans-serif; margin: 20px; }
h2 { color: #333; }
.info-box { background: #f0f0f0; color: #000; padding: 10px; font-family: monospace; text-align: left; border: 1px solid #ccc; margin-bottom: 20px; }
.tree { background: #fff; color: #000; padding: 10px; border: 1px solid #ccc; margin-bottom: 20px; font-family: monospace; }
.tree ul { list-style: none; padding-left: 20px; margin: 0; }
.tree li { margin: 5px 0; position: relative; }
.tree .toggle { cursor: pointer; user-select: none; margin-right: 5px; color: #666; }
.tree .dir > span { cursor: pointer; font-weight: bold; }
.tree .file, .tree .dir { padding: 2px 0; }
.icon { margin-right: 5px; }
</style>
</head>
<body>
EOF

# --- БЛОК, ЗАВИСИМЫЙ ОТ РЕЖИМА 'diff' ---
if [ "$MODE" == "diff" ]; then
  cat >> report/files.html <<EOF
<h2>Сравнение коммитов</h2>
<div class="info-box">
<pre>
 Последний коммит: $LAST_COMMIT ($LAST_COMMIT_DATE)
 Коммит сравнения: $PREV_COMMIT ($PREV_COMMIT_DATE)
</pre>
</div>
EOF
fi

cat >> report/files.html << 'EOF'
<h2>Структура проекта</h2>
<div id="tree" class="tree">
  <ul id="root"></ul>
</div>
EOF

# --- БЛОК, ЗАВИСИМЫЙ ОТ РЕЖИМА 'diff' ---
if [ "$MODE" == "diff" ]; then
  cat >> report/files.html << 'EOF'
<h2>Изменения (Diff)</h2>
<iframe src="diff.html" style="width:100%; height:800px; border:1px solid #ccc;" frameborder="0"></iframe>
EOF
fi

cat >> report/files.html << 'EOF'
<script>
EOF

# Список файлов (всегда нужен)
files_list=$(git ls-files | LC_ALL=C sort | sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/;s/$/"/' | tr '\n' ',' | sed 's/,$//')
echo "const files = [$files_list];" >> report/files.html

# Статусы файлов (зависят от режима)
if [ "$MODE" == "diff" ]; then
  echo "const fileStatus = {" >> report/files.html
  first=1
  for key in "${!FILE_STATUS[@]}"; do
    if [ $first -eq 0 ]; then echo "," >> report/files.html; fi
    first=0
    escaped_key=$(echo "$key" | sed 's/\\/\\\\/g; s/"/\\"/g')
    echo "  \"$escaped_key\": \"${FILE_STATUS[$key]}\"" >> report/files.html
  done
  echo "};" >> report/files.html
else
  # В режиме 'structure' создаем пустой объект
  echo "const fileStatus = {};" >> report/files.html
fi


# JS для дерева (одинаковый для обоих режимов)
cat >> report/files.html << 'EOF'
function buildTree() {
  const root = { children: {}, fullpath: '', name: 'Root' };

  files.forEach(file => {
    const parts = file.split('/');
    let current = root;
    let currentPath = '';
    parts.forEach((part, index) => {
      currentPath += (currentPath ? '/' : '') + part;
      if (!current.children[part]) {
        current.children[part] = { 
          children: {}, 
          fullpath: currentPath, 
          name: part,
          isFile: index === parts.length - 1
        };
      }
      current = current.children[part];
    });
  });

  function renderNode(node, ul) {
    Object.keys(node.children).sort().forEach(childName => {
      const child = node.children[childName];
      const li = document.createElement('li');
      const icon = child.isFile ? '📄' : '📁';
      const span = document.createElement('span');
      span.innerHTML = `<span class="icon">${icon}</span>${child.name}`;
      
      if (fileStatus[child.fullpath]) {
        span.style.color = fileStatus[child.fullpath];
        span.style.fontWeight = 'bold';
      }
      
      li.appendChild(span);

      if (!child.isFile) {
        li.classList.add('dir');
        const toggle = document.createElement('span');
        toggle.classList.add('toggle');
        toggle.innerHTML = '▶';
        span.insertBefore(toggle, span.firstChild);
        
        const clickHandler = function(e) {
          e.stopPropagation();
          const childUl = li.querySelector('ul');
          const isExpanded = childUl.style.display === 'block';
          childUl.style.display = isExpanded ? 'none' : 'block';
          toggle.innerHTML = isExpanded ? '▶' : '▼';
        };
        toggle.onclick = clickHandler;
        span.onclick = clickHandler;

        const childUl = document.createElement('ul');
        li.appendChild(childUl);
        renderNode(child, childUl);
        childUl.style.display = 'none';
      }
      ul.appendChild(li);
    });
  }

  const rootUl = document.getElementById('root');
  renderNode(root, rootUl);
}

document.addEventListener('DOMContentLoaded', buildTree);
</script>
</body>
</html>
EOF

# Восстанавливаем Git
git config core.quotepath "$OLD_QUOTE"

mv report/files.html report/final_report.html

echo "[✓] Готово! Открывай report/final_report.html в браузере."
if [ "$MODE" == "diff" ]; then
    echo "(Diff отображается в iframe для сохранения стилей)"
fi