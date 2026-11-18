local addonName, Q = ...
local Core = Quintessence
Q.name, Q.version = addonName or 'quinte-ban', '0.6.0'
Q.menu, Q.alerted = 'indisponible', {}
-- Point d'accès facultatif pour le diagnostic du conteneur et les autres modules.
Core.Blacklist = Q

-- Saisie et petites fenêtres : composants communs du conteneur depuis 1.50.0 (S.OnText, S.TextArea, S.MakeDialog,
-- repris de cet addon). Les versions locales restent pour un conteneur plus ancien.
function Q.InputChanged(box,fn)
 local S=Core.Style
 if S.OnText then return S.OnText(box,fn) end
 local previous=box:GetScript('OnTextChanged')
 box:SetScript('OnTextChanged',function(self,...)
  if previous then previous(self,...) end
  fn(self,...)
 end)
end
-- Zone de commentaire sans loupe ni texte indicatif superposé, avec défilement du texte.
function Q.Comment(parent,width,height)
 local S=Core.Style
 if S.TextArea then return S.TextArea(parent,width,height,600) end
 local area=S.Box(parent,S.colors.raised,S.colors.line);area:SetSize(width,height)
 local scroll=CreateFrame('ScrollFrame',nil,area)
 scroll:SetPoint('TOPLEFT',2,-2);scroll:SetPoint('BOTTOMRIGHT',-2,2)
 local edit=CreateFrame('EditBox',nil,scroll)
 edit:SetWidth(width-4);edit:SetHeight(height-4);edit:SetMultiLine(true);edit:SetAutoFocus(false)
 if ChatFontNormal then edit:SetFontObject(ChatFontNormal) end
 edit:SetBlinkSpeed(0.5)
 edit:SetFont(STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF',12,'');edit:SetTextColor(unpack(S.colors.text))
 edit:SetPoint('TOPLEFT',scroll,'TOPLEFT',0,0);edit:EnableMouse(true);edit:EnableKeyboard(true)
 edit:SetTextInsets(1,1,0,0);edit:SetMaxLetters(600);scroll:SetScrollChild(edit)
 edit.container,edit.scroll=area,scroll
 area:EnableMouse(true);area:SetScript('OnMouseDown',function() edit:SetFocus() end)
 scroll:EnableMouse(true);scroll:SetScript('OnMouseDown',function() edit:SetFocus() end)
 edit:SetScript('OnEditFocusGained',function() area:SetBackdropBorderColor(unpack(S.colors.gold)) end)
 edit:SetScript('OnEditFocusLost',function() area:SetBackdropBorderColor(unpack(S.colors.line)) end)
 area:Show();scroll:Show();edit:Show()
 local function wheel(_,delta)
  local maximum=math.max(0,scroll:GetVerticalScrollRange() or 0)
  scroll:SetVerticalScroll(math.max(0,math.min(maximum,(scroll:GetVerticalScroll() or 0)-delta*24)))
 end
 scroll:EnableMouseWheel(true);scroll:SetScript('OnMouseWheel',wheel)
 edit:EnableMouseWheel(true);edit:SetScript('OnMouseWheel',wheel)
 edit:SetScript('OnCursorChanged',function(self,_,y,_,h)
  if type(y)~='number' or type(h)~='number' then return end
  local top=scroll:GetVerticalScroll() or 0;local visible=height-4;local cursor=-y
  local required=cursor+h+4;if required>(self:GetHeight() or 0) then self:SetHeight(required) end
  if cursor<top then scroll:SetVerticalScroll(math.max(0,cursor))
  elseif cursor+h>top+visible then scroll:SetVerticalScroll(math.max(0,cursor+h-visible)) end
 end)
 edit:SetScript('OnTextChanged',function(self)
  if (self:GetText() or '')=='' then self:SetHeight(height-4);scroll:SetVerticalScroll(0) end
 end)
 return edit
end

-- Fenêtres possédées par l’addon : déplacement par le titre, fermeture et premier plan.
function Q.Dialog(frame,width,height)
 local S=Core.Style
 if S.MakeDialog then return S.MakeDialog(frame,width,height) end
 frame:SetSize(width,height);frame:SetFrameStrata('DIALOG');frame:SetFrameLevel(300)
 frame:SetMovable(true);frame:SetClampedToScreen(true);frame:EnableMouse(true)
 frame.drag=CreateFrame('Frame',nil,frame);frame.drag:SetPoint('TOPLEFT',0,0);frame.drag:SetPoint('TOPRIGHT',-36,0);frame.drag:SetHeight(32)
 frame.drag:EnableMouse(true);frame.drag:RegisterForDrag('LeftButton')
 frame.drag:SetScript('OnDragStart',function() frame:StartMoving() end)
 frame.drag:SetScript('OnDragStop',function() frame:StopMovingOrSizing() end)
 frame:SetScript('OnHide',function()
  frame:StopMovingOrSizing()
  if frame.comment then frame.comment:ClearFocus() end
  if frame.name then frame.name:ClearFocus() end
 end)
 frame.close=S.Button(frame,'X',24,24,'ghost');frame.close:SetPoint('TOPRIGHT',-6,-6)
 frame.close:SetScript('OnClick',function() frame:Hide() end)
end
function Q.UnitClass(unit)
 if not unit then return end
 local ok,_,token=Core.Call(UnitClass,unit)
 if ok and not (issecretvalue and issecretvalue(token)) and type(token)=='string' then return token end
end
