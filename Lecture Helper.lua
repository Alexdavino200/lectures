script_name("Lecture Helper")
script_author("User & Gemini")
script_version("4.0") -- Текущая версия скрипта

require "lib.moonloader"
local imgui = require "mimgui"
local encoding = require "encoding"
local ffi = require "ffi"

encoding.default = 'CP1251'
local u8 = encoding.UTF8

-- ==========================================================
-- ССЫЛКА НА ФАЙЛ СКРИПТА (ВЛОЖЕНИЕ ИЗ ДИСКОРДА)
-- ==========================================================
local UPDATE_URL = "СЮДА_ВСТАВЬ_ССЫЛКУ_ИЗ_ДИСКОРДА"

function chatMsg(text)
    sampAddChatMessage(u8:decode(text), -1)
end

local config_dir = getWorkingDirectory() .. "\\config"
local config_path = config_dir .. "\\lectures.json"
local this_script_path = select(2, ... )

local renderWindow = imgui.new.bool(false)
local delay_sec = imgui.new.int(3)
local is_playing = false

local selected_cat = 1
local selected_lec = 1
local selected_kmb = 1

local edit_title_buf = imgui.new.char[256]()
local edit_text_buf = imgui.new.char[8192]()
local kmb_q_buf = imgui.new.char[256]()
local kmb_a_buf = imgui.new.char[4096]()

-- База данных по умолчанию
local data = {
    delay = 3,
    categories = {
        {
            name = "Общие",
            lectures = {
                {
                    title = "Субординация",
                    lines = {
                        "/s Здравия желаю, бойцы! Сейчас пройдет лекция на тему «Субординация».",
                        "/s Субординация - это система служебных отношений, основанная на подчинении.",
                        "/s Обращаться к старшим по званию строго на «Вы» и по воинскому званию.",
                        "/s На этом лекция окончена. Вопросы есть?"
                    }
                }
            }
        },
        {
            name = "Агитации",
            lectures = {
                {
                    title = "Агитация в подразделение",
                    lines = {
                        "/s Минуточку внимания, бойцы!",
                        "/s Сейчас расскажу вам о преимуществах перевода в наш отдел."
                    }
                }
            }
        },
        {
            name = "ВМТО",
            lectures = {
                {
                    title = "Правила поставок боеприпасов",
                    lines = {
                        "/s Здравия желаю, сотрудники ВМТО!",
                        "/s Напоминаю правила проведения поставок на склады."
                    }
                }
            }
        },
        {
            name = "СВСС",
            lectures = {
                {
                    title = "Охрана стратегических объектов",
                    lines = {
                        "/s Бойцы СВСС, минутку внимания!",
                        "/s Разберем регламент несения службы на постах."
                    }
                }
            }
        },
        {
            name = "КМБ",
            is_kmb = true,
            questions = {
                {
                    question = "Что такое субординация?",
                    answer = "Субординация — это система служебных отношений, связанных с подчинением."
                },
                {
                    question = "Что запрещено в строю?",
                    answer = "В строю запрещено разговаривать, использовать телефоны, доставать оружие и выходить без разрешения."
                }
            }
        }
    }
}

function textToLines(text)
    local lines = {}
    for line in text:gmatch("[^\r\n]+") do
        if line:match("%S") then
            table.insert(lines, line)
        end
    end
    return lines
end

function linesToText(lines)
    if type(lines) == "table" then
        return table.concat(lines, "\n")
    end
    return ""
end

function toPrettyJson(val, indent)
    indent = indent or 0
    local pad = string.rep("  ", indent)
    local next_pad = string.rep("  ", indent + 1)

    if type(val) == "table" then
        local is_array = (#val > 0)
        if is_array then
            local items = {}
            for i = 1, #val do
                table.insert(items, next_pad .. toPrettyJson(val[i], indent + 1))
            end
            return "[\n" .. table.concat(items, ",\n") .. "\n" .. pad .. "]"
        else
            local items = {}
            local key_order = {"delay", "categories", "name", "lectures", "title", "lines", "is_kmb", "questions", "question", "answer"}
            local used = {}
            for _, k in ipairs(key_order) do
                if val[k] ~= nil then
                    table.insert(items, next_pad .. '"' .. k .. '": ' .. toPrettyJson(val[k], indent + 1))
                    used[k] = true
                end
            end
            for k, v in pairs(val) do
                if not used[k] then
                    table.insert(items, next_pad .. '"' .. tostring(k) .. '": ' .. toPrettyJson(v, indent + 1))
                end
            end
            return "{\n" .. table.concat(items, ",\n") .. "\n" .. pad .. "}"
        end
    elseif type(val) == "string" then
        local escaped = val:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\r', ''):gsub('\n', '\\n')
        return '"' .. escaped .. '"'
    elseif type(val) == "number" or type(val) == "boolean" then
        return tostring(val)
    else
        return "null"
    end
end

function saveData()
    if not doesDirectoryExist(config_dir) then
        createDirectory(config_dir)
    end
    data.delay = delay_sec[0]
    local file = io.open(config_path, "w")
    if file then
        file:write(toPrettyJson(data))
        file:close()
    end
end

function loadLocalData(is_manual)
    if doesFileExist(config_path) then
        local file = io.open(config_path, "r")
        if file then
            local content = file:read("*a")
            file:close()
            local status, decoded = pcall(decodeJson, content)
            if status and type(decoded) == "table" and decoded.categories then
                data = decoded
                delay_sec[0] = data.delay or 3

                if selected_cat > #data.categories then selected_cat = 1 end
                local cat = data.categories[selected_cat]
                if cat.is_kmb then
                    if selected_kmb > #(cat.questions or {}) then selected_kmb = math.max(1, #(cat.questions or {})) end
                else
                    if selected_lec > #(cat.lectures or {}) then selected_lec = math.max(1, #(cat.lectures or {})) end
                end

                updateBuffers()
                if is_manual then
                    chatMsg("{00BFFF}[Lecture Helper]{FFFFFF} Данные успешно обновлены из файла!")
                end
                return true
            else
                if is_manual then
                    chatMsg("{00BFFF}[Lecture Helper]{FF4444} Ошибка чтения JSON в файле!")
                end
                return false
            end
        end
    end
    if not is_manual then
        saveData()
    end
    return false
end

-- Функция автообновления через Discord
function checkForUpdates()
    if UPDATE_URL == "" or UPDATE_URL:find("СЮДА_ВСТАВЬ") then return end

    local temp_path = config_dir .. "\\temp_update.lua"
    downloadUrlToFile(UPDATE_URL, temp_path, function(id, status, p1, p2)
        if status == dlstatus.DOWNLOAD_COMPLETE then
            local file = io.open(temp_path, "r")
            if file then
                local content = file:read("*a")
                file:close()
                os.remove(temp_path)

                local remote_version = content:match('script_version%s*%(%s*["\']([^"\']+)["\']%s*%)')
                
                if remote_version and remote_version ~= this_script_version then
                    chatMsg(string.format("{00BFFF}[Lecture Helper]{FFFFFF} Найдена новая версия ({00BFFF}%s{FFFFFF}). Скачиваю...", remote_version))
                    
                    downloadUrlToFile(UPDATE_URL, this_script_path, function(id2, status2)
                        if status2 == dlstatus.DOWNLOAD_COMPLETE then
                            chatMsg("{00BFFF}[Lecture Helper]{FFFFFF} Обновление установлено! Перезагружаю скрипт...")
                            this_script():reload()
                        end
                    end)
                end
            end
        end
    end)
end

local this_script_version = "4.0"

function updateBuffers()
    local cat = data.categories[selected_cat]
    if not cat then selected_cat = 1; cat = data.categories[1] end

    if cat.is_kmb then
        local q = cat.questions and cat.questions[selected_kmb]
        if q then
            imgui.StrCopy(kmb_q_buf, q.question or "")
            imgui.StrCopy(kmb_a_buf, q.answer or "")
        else
            imgui.StrCopy(kmb_q_buf, "")
            imgui.StrCopy(kmb_a_buf, "")
        end
    else
        local lec = cat.lectures and cat.lectures[selected_lec]
        if lec then
            imgui.StrCopy(edit_title_buf, lec.title or "")
            imgui.StrCopy(edit_text_buf, linesToText(lec.lines))
        else
            imgui.StrCopy(edit_title_buf, "")
            imgui.StrCopy(edit_text_buf, "")
        end
    end
end

function applyCustomTheme()
    imgui.SwitchContext()
    local style = imgui.GetStyle()
    local colors = style.Colors
    local clr = imgui.Col
    local ImVec4 = imgui.ImVec4
    local ImVec2 = imgui.ImVec2

    style.WindowPadding = ImVec2(12, 12)
    style.WindowRounding = 10.0
    style.ChildRounding = 8.0
    style.FramePadding = ImVec2(8, 5)
    style.FrameRounding = 6.0
    style.ItemSpacing = ImVec2(8, 8)
    style.WindowTitleAlign = ImVec2(0.5, 0.5)

    colors[clr.Text]                   = ImVec4(0.95, 0.96, 0.98, 1.00)
    colors[clr.TextDisabled]           = ImVec4(0.50, 0.55, 0.60, 1.00)
    colors[clr.WindowBg]               = ImVec4(0.11, 0.12, 0.15, 0.98)
    colors[clr.ChildBg]                = ImVec4(0.14, 0.15, 0.19, 1.00)
    colors[clr.Border]                 = ImVec4(0.22, 0.24, 0.30, 0.60)
    colors[clr.FrameBg]                = ImVec4(0.16, 0.18, 0.22, 1.00)
    colors[clr.FrameBgHovered]         = ImVec4(0.20, 0.22, 0.28, 1.00)
    colors[clr.FrameBgActive]          = ImVec4(0.24, 0.27, 0.34, 1.00)
    colors[clr.TitleBg]                = ImVec4(0.09, 0.10, 0.13, 1.00)
    colors[clr.TitleBgActive]          = ImVec4(0.12, 0.14, 0.18, 1.00)
    colors[clr.Button]                 = ImVec4(0.18, 0.20, 0.26, 1.00)
    colors[clr.ButtonHovered]          = ImVec4(0.24, 0.27, 0.35, 1.00)
    colors[clr.ButtonActive]           = ImVec4(0.20, 0.48, 0.85, 1.00)
    colors[clr.Header]                 = ImVec4(0.20, 0.48, 0.85, 0.45)
    colors[clr.HeaderHovered]          = ImVec4(0.24, 0.54, 0.92, 0.65)
end

imgui.OnInitialize(function()
    applyCustomTheme()
end)

function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end

    if not loadLocalData(false) then
        saveData()
    end
    updateBuffers()

    -- Фоновая проверка обновлений из Discord через 2 секунды после запуска
    lua_thread.create(function()
        wait(2000)
        checkForUpdates()
    end)

    chatMsg("{00BFFF}[Lecture Helper]{FFFFFF} Скрипт успешно запущен! Меню: {00BFFF}/lec")

    sampRegisterChatCommand("lec", function()
        renderWindow[0] = not renderWindow[0]
        imgui.Process = renderWindow[0]
    end)

    wait(-1)
end

imgui.OnFrame(
    function() 
        if not renderWindow[0] then imgui.Process = false end
        return renderWindow[0] 
    end,
    function(player)
        local sw, sh = getScreenResolution()
        imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(740, 500), imgui.Cond.FirstUseEver)

        if imgui.Begin("Помощник лектора и экзаменатора", renderWindow, imgui.WindowFlags.NoCollapse) then
            
            local total_cats = #data.categories
            local btn_width = (720 - (total_cats - 1) * 6) / total_cats
            
            for i, cat in ipairs(data.categories) do
                if i > 1 then imgui.SameLine() end
                local is_selected = (selected_cat == i)
                if is_selected then
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.20, 0.52, 0.90, 1.00))
                end
                if imgui.Button(cat.name, imgui.ImVec2(btn_width, 32)) then
                    selected_cat = i
                    selected_lec = 1
                    selected_kmb = 1
                    updateBuffers()
                end
                if is_selected then
                    imgui.PopStyleColor(1)
                end
            end

            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            local cat = data.categories[selected_cat]

            -- РАЗДЕЛ КМБ
            if cat.is_kmb then
                imgui.Columns(2, "KMBColumns", true)
                imgui.SetColumnWidth(-1, 240)

                imgui.Text("Список вопросов:")
                imgui.BeginChild("KMBList", imgui.ImVec2(225, 335), true)
                for i, q in ipairs(cat.questions or {}) do
                    if imgui.Selectable(q.question .. "##" .. i, selected_kmb == i) then
                        selected_kmb = i
                        updateBuffers()
                    end
                end
                imgui.EndChild()

                if imgui.Button("+ Вопрос", imgui.ImVec2(108, 30)) then
                    table.insert(cat.questions, {
                        question = "Новый вопрос?",
                        answer = "Ответ на вопрос..."
                    })
                    selected_kmb = #cat.questions
                    updateBuffers()
                    saveData()
                end
                imgui.SameLine()
                if imgui.Button("- Удалить", imgui.ImVec2(108, 30)) then
                    if #cat.questions > 1 then
                        table.remove(cat.questions, selected_kmb)
                        if selected_kmb > #cat.questions then selected_kmb = #cat.questions end
                        updateBuffers()
                        saveData()
                    else
                        chatMsg("{00BFFF}[Lecture Helper]{FFFFFF} Должен остаться хотя бы один вопрос!")
                    end
                end

                imgui.NextColumn()

                imgui.Text("Редактирование вопроса КМБ:")
                imgui.PushItemWidth(-1)
                imgui.InputText("##KMBQ", kmb_q_buf, ffi.sizeof(kmb_q_buf))
                imgui.PopItemWidth()

                imgui.Spacing()
                imgui.Text("Правильный ответ:")
                imgui.InputTextMultiline("##KMBA", kmb_a_buf, ffi.sizeof(kmb_a_buf), imgui.ImVec2(-1, 160))

                imgui.Spacing()

                if imgui.Button("Сохранить", imgui.ImVec2(110, 32)) then
                    local q = cat.questions[selected_kmb]
                    if q then
                        q.question = ffi.string(kmb_q_buf)
                        q.answer = ffi.string(kmb_a_buf)
                        saveData()
                        chatMsg("{00BFFF}[Lecture Helper]{FFFFFF} Вопрос КМБ сохранен локально!")
                    end
                end

                imgui.SameLine()

                if imgui.Button("Обновить из файла", imgui.ImVec2(145, 32)) then
                    loadLocalData(true)
                    updateBuffers()
                end

                imgui.SameLine()

                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.16, 0.62, 0.32, 1.00))
                if imgui.Button("Задать", imgui.ImVec2(-1, 32)) then
                    local q = cat.questions[selected_kmb]
                    if q and q.question ~= "" then
                        sampSendChat(u8:decode(q.question))
                    end
                end
                imgui.PopStyleColor(1)

                imgui.Columns(1)

            -- ОБЫЧНЫЕ ЛЕКЦИИ
            else
                imgui.Columns(2, "MainColumns", true)
                imgui.SetColumnWidth(-1, 225)

                imgui.Text("Список лекций:")
                imgui.BeginChild("LectureList", imgui.ImVec2(210, 335), true)
                local current_lectures = cat.lectures
                for i, lec in ipairs(current_lectures) do
                    if imgui.Selectable(lec.title .. "##" .. i, selected_lec == i) then
                        selected_lec = i
                        updateBuffers()
                    end
                end
                imgui.EndChild()

                if imgui.Button("+ Добавить", imgui.ImVec2(100, 30)) then
                    table.insert(current_lectures, {
                        title = "Новая лекция",
                        lines = { "/s Введите текст новой лекции..." }
                    })
                    selected_lec = #current_lectures
                    updateBuffers()
                    saveData()
                end
                imgui.SameLine()
                if imgui.Button("- Удалить", imgui.ImVec2(100, 30)) then
                    if #current_lectures > 1 then
                        table.remove(current_lectures, selected_lec)
                        if selected_lec > #current_lectures then selected_lec = #current_lectures end
                        updateBuffers()
                        saveData()
                    else
                        chatMsg("{00BFFF}[Lecture Helper]{FFFFFF} В категории должна оставаться хотя бы одна лекция!")
                    end
                end

                imgui.NextColumn()

                imgui.PushItemWidth(160)
                if imgui.SliderInt("Задержка (сек.)", delay_sec, 1, 15) then
                    saveData()
                end
                imgui.PopItemWidth()

                imgui.Spacing()
                imgui.Text("Название лекции:")
                imgui.PushItemWidth(-1)
                imgui.InputText("##EditTitle", edit_title_buf, ffi.sizeof(edit_title_buf))
                imgui.PopItemWidth()

                imgui.Spacing()
                imgui.Text("Текст лекции (каждая строка = новое сообщение):")
                imgui.InputTextMultiline("##EditText", edit_text_buf, ffi.sizeof(edit_text_buf), imgui.ImVec2(-1, 160))

                imgui.Spacing()

                if imgui.Button("Сохранить", imgui.ImVec2(110, 32)) then
                    local lec = current_lectures[selected_lec]
                    if lec then
                        lec.title = ffi.string(edit_title_buf)
                        lec.lines = textToLines(ffi.string(edit_text_buf))
                        saveData()
                        chatMsg("{00BFFF}[Lecture Helper]{FFFFFF} Изменения сохранены локально!")
                    end
                end

                imgui.SameLine()

                if imgui.Button("Обновить из файла", imgui.ImVec2(145, 32)) then
                    loadLocalData(true)
                    updateBuffers()
                end

                imgui.SameLine()

                if not is_playing then
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.16, 0.62, 0.32, 1.00))
                    if imgui.Button("Начать лекцию", imgui.ImVec2(-1, 32)) then
                        local lec = current_lectures[selected_lec]
                        if lec then
                            lec.title = ffi.string(edit_title_buf)
                            lec.lines = textToLines(ffi.string(edit_text_buf))
                            saveData()
                            startLecture(lec.lines, delay_sec[0])
                        end
                    end
                    imgui.PopStyleColor(1)
                else
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.78, 0.22, 0.22, 1.00))
                    if imgui.Button("Остановить", imgui.ImVec2(-1, 32)) then
                        is_playing = false
                        chatMsg("{00BFFF}[Lecture Helper]{FFFFFF} Чтение лекции остановлено.")
                    end
                    imgui.PopStyleColor(1)
                end

                imgui.Columns(1)
            end
        end
        imgui.End()
    end
)

function startLecture(lines, delay)
    lua_thread.create(function()
        is_playing = true
        chatMsg("{00BFFF}[Lecture Helper]{FFFFFF} Начинаю зачитывать лекцию...")
        
        for _, line in ipairs(lines) do
            if not is_playing then break end
            
            if line:match("%S") then
                sampSendChat(u8:decode(line))
                wait(delay * 1000)
            end
        end
        
        if is_playing then
            chatMsg("{00BFFF}[Lecture Helper]{FFFFFF} Лекция завершена!")
            is_playing = false
        end
    end)
end