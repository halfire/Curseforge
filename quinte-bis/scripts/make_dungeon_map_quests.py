"""Copie reproductible du catalogue de quêtes Forever pour les plans BiS autonomes.
La logique de journal/partage reste dans quinte-group ; seuls les faits générés sont copiés.
Usage : python3 scripts/make_dungeon_map_quests.py
"""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
for source,target in [('DungeonQuests.lua','DungeonMapQuests.lua'),('DungeonQuestInfo.lua','DungeonMapQuestInfo.lua')]:
 text=(root.parent/'quinte-group'/source).read_text().replace('Q.DUNGEON_QUESTS','Q.DUNGEON_MAP_QUESTS').replace('Q.DUNGEON_QUEST_INFO','Q.DUNGEON_MAP_QUEST_INFO')
 (root/target).write_text('-- Copie générée par scripts/make_dungeon_map_quests.py depuis quinte-group/'+source+'.\n'+text)
print('Catalogue des quêtes et conditions des plans régénéré')
