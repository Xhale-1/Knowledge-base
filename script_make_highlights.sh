#!/bin/bash

# --- НАСТРОЙКИ ---
SOURCE_DIR="Knowledge Base"
OUTPUT_DIR="highlights"
OUTPUT_FILENAME="all_highlights.docx"
TEMP_TXT_FILE="${OUTPUT_DIR}/_temp_highlights.txt"
FINAL_OUTPUT_PATH="${OUTPUT_DIR}/${OUTPUT_FILENAME}"
LINES_TO_GRAB=150

# --- ПРОВЕРКИ ---
if ! command -v pandoc &> /dev/null; then
    echo "Ошибка: утилита 'pandoc' не найдена."
    exit 1
fi
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Ошибка: Директория '$SOURCE_DIR' не найдена."
    exit 1
fi

# --- ВЫПОЛНЕНИЕ ---
echo "Начинаю обработку файлов..."
mkdir -p "$OUTPUT_DIR"
rm -f "$TEMP_TXT_FILE" "$FINAL_OUTPUT_PATH"
touch "$TEMP_TXT_FILE"

# --- ОТЛАДКА: Считаем найденные файлы ---
file_count=0

find "$SOURCE_DIR" -type f -name "*.docx" -print0 | while IFS= read -r -d '' docx_file; do
    echo "-> Обрабатываю файл: $docx_file"
    
    # Увеличиваем счетчик
    ((file_count++))

    echo -e "\n\n==================================================" >> "$TEMP_TXT_FILE"
    echo "ИСТОЧНИК: $docx_file" >> "$TEMP_TXT_FILE"
    echo "==================================================\n" >> "$TEMP_TXT_FILE"

    # Добавляем &> /dev/null чтобы скрыть возможные ошибки от pandoc на каждый файл
    pandoc -f docx -t plain "$docx_file" 2>/dev/null | head -n $LINES_TO_GRAB >> "$TEMP_TXT_FILE"
done

# --- АНАЛИЗ ПОСЛЕ ЦИКЛА ---

# Проверяем, существует ли временный файл и не пустой ли он
if [ -s "$TEMP_TXT_FILE" ]; then
    echo "Временный файл _temp_highlights.txt успешно создан и содержит данные."
    echo "Создаю итоговый .docx файл..."
    
    # Конвертируем наш собранный текстовый файл обратно в формат .docx
    pandoc -f markdown -t docx "$TEMP_TXT_FILE" -o "$FINAL_OUTPUT_PATH"
    
    # Проверяем, создался ли финальный файл
    if [ -f "$FINAL_OUTPUT_PATH" ]; then
        echo "Готово! Все выдержки сохранены в файл: $FINAL_OUTPUT_PATH"
        # Раскомментируйте следующую строку, когда убедитесь, что все работает
        # rm "$TEMP_TXT_FILE"
        echo "Временный файл _temp_highlights.txt оставлен для проверки."
    else
        echo "Ошибка: Не удалось создать финальный файл $FINAL_OUTPUT_PATH с помощью pandoc."
        echo "Попробуйте запустить команду вручную:"
        echo "pandoc -f markdown -t docx \"$TEMP_TXT_FILE\" -o \"$FINAL_OUTPUT_PATH\""
    fi
else
    echo "Ошибка: Временный файл _temp_highlights.txt пуст или не был создан."
    echo "Возможные причины:"
    echo "1. Не было найдено ни одного .docx файла в директории '$SOURCE_DIR'."
    echo "2. Произошли ошибки при чтении всех найденных файлов с помощью pandoc."
    echo "Пожалуйста, проверьте имя директории и наличие в ней .docx файлов."
fi