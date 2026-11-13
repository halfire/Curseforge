local _, Q = ...
-- Lecture embarquée des guides du site : aucun réseau, aucune sauvegarde ou synchro supplémentaire.
local S = Quintessence.Style
local panel, guideIndex, chapterIndex, scrollOffset = nil, 1, 1, 0
local function read(fn, ...)
    local ok, value = Q.Call(fn, ...)
    if ok and not (issecretvalue and issecretvalue(value)) then return value end
end
local function tooltip(owner, kind, id)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, 'ANCHOR_RIGHT')
    Q.Call(GameTooltip.SetHyperlink, GameTooltip, kind .. ':' .. id)
    GameTooltip:Show()
end
local function hideTooltip() if GameTooltip then GameTooltip:Hide() end end
local function applyScroll(value)
    scrollOffset = math.max(0, math.min(value, panel.scrollMax or 0))
    panel.reader:SetVerticalScroll(scrollOffset)
    if panel.scroll:GetValue() ~= scrollOffset then panel.scroll:SetValue(scrollOffset) end
end
local function blockFrame(index)
    local row = panel.blocks[index]
    if row then return row end
    row = S.Box(panel.body, S.colors.bg, S.colors.line)
    row:SetWidth(panel.readerWidth)
    row.heading = S.Text(row, 13, S.colors.gold)
    row.heading:SetPoint('TOPLEFT', 12, -12); row.heading:SetWidth(panel.readerWidth - 190)
    row.heading:SetWordWrap(true)
    row.text = S.Text(row, 12, S.colors.text)
    row.text:SetPoint('TOPLEFT', 12, -40); row.text:SetWidth(panel.readerWidth - 26)
    row.text:SetWordWrap(true)
    row.map = S.Button(row, 'Carte', 54, 22, 'ghost'); row.map:SetPoint('TOPRIGHT', -10, -8)
    row.map:SetScript('OnClick', function() Q.Run('repère du guide', Q.ShowGuidePlace, row.block.point, row.block.heading) end)
    row.link = S.Button(row, '', 82, 22, 'ghost'); row.link:SetPoint('RIGHT', row.map, 'LEFT', -6, 0)
    row.link:SetScript('OnEnter', function(self)
        local b = row.block
        if b.quest or b.item then tooltip(self, b.quest and 'quest' or 'item', b.quest or b.item) end
    end)
    row.link:SetScript('OnLeave', hideTooltip)
    row.link:SetScript('OnClick', function(self)
        local b = row.block
        if b.item then
            if not Quintessence.LinkItem(b.item) then tooltip(self, 'item', b.item) end
        elseif b.quest then tooltip(self, 'quest', b.quest) end
    end)
    panel.blocks[index] = row
    return row
end
function Q.RefreshGuides()
    if not panel or not panel:IsVisible() then return end
    local guide = (Q.GUIDES or {})[guideIndex]
    if not guide then panel.title:SetText('Aucun guide disponible.'); return end
    chapterIndex = math.min(chapterIndex, #guide.chapters)
    local chapter = guide.chapters[chapterIndex]
    panel.title:SetText(Q.Safe(guide.title))
    panel.subtitle:SetText(Q.Safe(guide.subtitle) .. ' · Copie du site fournie avec cet addon')
    panel.source:SetText(guide.url)
    for i, button in ipairs(panel.guideButtons) do button:SetActive(i == guideIndex) end
    for i = 1, math.max(#guide.chapters, #panel.chapterButtons) do
        local button = panel.chapterButtons[i]
        if not button then
            button = S.Button(panel.left, '', 230, 26, 'ghost')
            button:SetPoint('TOPLEFT', 10, -panel.chapterTop - (i - 1) * 30)
            button:SetScript('OnClick', function() chapterIndex = i; scrollOffset = 0; Q.RefreshGuides() end)
            panel.chapterButtons[i] = button
        end
        button:SetShown(guide.chapters[i] ~= nil)
        if guide.chapters[i] then button:SetLabel(guide.chapters[i].title); button:SetActive(i == chapterIndex) end
    end
    local y = 0
    for i, block in ipairs(chapter and chapter.blocks or {}) do
        local row = blockFrame(i)
        row.block = block; row:ClearAllPoints(); row:SetPoint('TOPLEFT', 0, -y); row:Show()
        local title = block.heading
        if block.quest then
            local state = read(C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted, block.quest) == true and 'Terminée'
                or read(C_QuestLog and C_QuestLog.IsOnQuest, block.quest) == true and 'En cours' or 'À prendre / prérequis à vérifier'
            title = title .. ' · ' .. state
        end
        row.heading:SetText(Q.Safe(title)); row.heading:SetHeight(0)
        local titleHeight = row.heading:GetStringHeight()
        row.text:ClearAllPoints(); row.text:SetPoint('TOPLEFT', 12, -20 - titleHeight)
        row.text:SetText(Q.Safe(block.text)); row.text:SetHeight(0)
        local height = math.ceil(34 + titleHeight + row.text:GetStringHeight())
        row:SetHeight(height); y = y + height + 10
        row.map:SetShown(block.point ~= nil)
        row.link:SetShown(block.quest ~= nil or block.item ~= nil)
        row.link:SetLabel(block.quest and 'Quête' or 'Objet')
        row.link:ClearAllPoints()
        if block.point then row.link:SetPoint('RIGHT', row.map, 'LEFT', -6, 0)
        else row.link:SetPoint('TOPRIGHT', -10, -8) end
    end
    for i = #(chapter and chapter.blocks or {}) + 1, #panel.blocks do panel.blocks[i]:Hide() end
    panel.body:SetHeight(math.max(1, y))
    panel.scrollMax = math.max(0, y - panel.readerHeight)
    panel.scroll:SetMinMaxValues(0, panel.scrollMax)
    applyScroll(scrollOffset)
end
function Q.CreateGuidesPanel(parent, width, height)
    panel = CreateFrame('Frame', nil, parent); panel:SetAllPoints()
    panel.left = S.Box(panel, S.colors.panel, S.colors.line)
    panel.left:SetPoint('TOPLEFT'); panel.left:SetSize(250, height)
    local heading = S.Heading(panel.left, 'Guide Quintessence'); heading:SetPoint('TOPLEFT', 12, -12)
    panel.guideButtons, panel.chapterButtons, panel.blocks = {}, {}, {}
    for i, guide in ipairs(Q.GUIDES or {}) do
        local button = S.Button(panel.left, guide.title, 230, 40, 'ghost')
        button:SetPoint('TOPLEFT', 10, -40 - (i - 1) * 44)
        button.label:SetWordWrap(true)
        button:SetScript('OnClick', function() guideIndex, chapterIndex, scrollOffset = i, 1, 0; Q.RefreshGuides() end)
        panel.guideButtons[i] = button
    end
    panel.chapterTop = 84 + #panel.guideButtons * 44
    local chapters = S.Heading(panel.left, 'Sommaire'); chapters:SetPoint('TOPLEFT', 12, -panel.chapterTop + 26)
    local right = S.Box(panel, S.colors.panel, S.colors.line)
    right:SetPoint('TOPLEFT', 262, 0); right:SetSize(width - 262, height)
    panel.title = S.Text(right, 15, S.colors.gold); panel.title:SetPoint('TOPLEFT', 12, -12); panel.title:SetWidth(width - 290)
    panel.subtitle = S.Text(right, 11, S.colors.muted); panel.subtitle:SetPoint('TOPLEFT', 12, -36); panel.subtitle:SetWidth(width - 290)
    panel.source = S.Input(right, width - 294, 'Adresse du guide sur le site')
    panel.source:SetPoint('BOTTOMLEFT', 12, 10)
    panel.source:SetScript('OnEditFocusGained', function(self) self:HighlightText() end)
    panel.readerWidth, panel.readerHeight = width - 306, height - 100
    panel.reader = CreateFrame('ScrollFrame', nil, right)
    panel.reader:SetPoint('TOPLEFT', 12, -62); panel.reader:SetSize(panel.readerWidth, panel.readerHeight)
    panel.body = CreateFrame('Frame', nil, panel.reader); panel.body:SetWidth(panel.readerWidth); panel.body:SetHeight(1)
    panel.reader:SetScrollChild(panel.body)
    panel.scroll = S.Scrollbar(right, panel.readerHeight, function(value) applyScroll(value) end)
    panel.scroll:SetPoint('TOPRIGHT', -8, -62)
    panel.reader:EnableMouseWheel(true)
    panel.reader:SetScript('OnMouseWheel', function(_, delta) applyScroll(scrollOffset - delta * 45) end)
    panel:SetScript('OnShow', function() Q.Run('lecture guide', Q.RefreshGuides) end)
    local events = CreateFrame('Frame')
    for _, event in ipairs({'QUEST_LOG_UPDATE', 'QUEST_TURNED_IN', 'QUEST_ACCEPTED', 'QUEST_REMOVED'}) do Q.Call(events.RegisterEvent, events, event) end
    events:SetScript('OnEvent', function() Q.Run('état des quêtes du guide', Q.RefreshGuides) end)
    return panel
end
