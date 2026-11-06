-- Compatibilité minimale pour les vieux clients. Ne JAMAIS réassigner une table ou une fonction de Blizzard :
-- sur Retail 12+, une écriture (même identique) contamine ensuite tout le code Blizzard qui la lit
-- (« execution tainted by … ») et le prive des valeurs secrètes. On ne crée donc que ce qui manque.
if type(C_ChatInfo) ~= 'table' then
    C_ChatInfo = {}
end
if C_ChatInfo.SendAddonMessage == nil and SendAddonMessage then
    C_ChatInfo.SendAddonMessage = SendAddonMessage
end
if C_ChatInfo.RegisterAddonMessagePrefix == nil and RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix = RegisterAddonMessagePrefix
end
if type(Enum) ~= 'table' then
    Enum = {}
end
