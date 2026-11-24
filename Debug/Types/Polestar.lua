-- Types for the Polestar surface this addon calls, and for its own rows.
-- Comments only: the language server reads this file, the game does not.

---@class PQI_Player
---@field faction string?
---@field race string?
---@field class string?

---@class PQI_Only
---@field classes string[]?
---@field races string[]?
---@field factions string[]?

---@class PQI_Goal
---@field quest number?
---@field only PQI_Only?
---@field t string?
---@field item number?

---@class PQI_Step
---@field only PQI_Only?
---@field goals PQI_Goal[]?

---@class PQI_Guide
---@field id string
---@field title string?
---@field dungeon string?
---@field faction string?
---@field steps PQI_Step[]?
---@field only PQI_Only?

---@class PQI_Hit
---@field key string
---@field title string
---@field why string?
---@field dungeon string?

---@alias PQI_HitMap table<number, PQI_Hit[]>
---@alias PQI_ItemMap table<number, number[]>

---@class PQI_DungeonMark
---@field key string
---@field quest number?
---@field breadcrumb boolean?

---@class PQI_Dungeon
---@field name string?

---@class PQI_Guides
---@field List fun(): PQI_Guide[]
---@field Get fun(id: string): PQI_Guide?
---@field Release fun(id: string)
---@field Matches fun(only: PQI_Only?, player: PQI_Player): boolean
---@field GuideMatches fun(g: PQI_Guide, player: PQI_Player): boolean
---@field OtherFaction fun(g: PQI_Guide, player: PQI_Player): boolean?
---@field OtherStart fun(g: PQI_Guide, player: PQI_Player): boolean?

---@class PQI_Compat
---@field Readable fun(value: any): string|number|nil
---@field GetPlayerInfo fun(): PQI_Player?
---@field InCombat fun(): boolean
---@field IsQuestCompleted fun(questID: number): boolean
---@field IsOnQuest fun(questID: number): boolean

---@class PQI_Names
---@field Quest fun(id: number): string?

---@class PQI_QuestDB
---@field GetQuestTitle fun(id: number): string?
---@field StartedBy fun(itemID: number): number[]?

---@class PQI_Dungeons
---@field QuestMark fun(id: number): PQI_DungeonMark?
---@field Meta fun(): any
---@field Load fun()
---@field Get fun(key: string): PQI_Dungeon?
---@field Open fun(key: string)

---@class PQI_Theme
---@field Media fun(name: string): string
---@field TipColor fun(key: string): number?, number?, number?
---@field Color fun(key: string): number, number, number

---@class PQI_Hooks
---@field ItemLines fun(owner: string, fn: fun(tooltip: GameTooltip, link: string?, itemID: number?))

---@class PQI_Widgets
---@field ScrollTo fun(scroll: ScrollFrame, offset: number)

---@class PQI_PickerRow : Frame
---@field psGuide PQI_Guide?

---@class PQI_PickerFrame : Frame
---@field Body Frame
---@field Scroll ScrollFrame

---@class PQI_Picker
---@field frame PQI_PickerFrame?
---@field scroll ScrollFrame?
---@field ShowSection fun(key: string?)
---@field SetQuery fun(text: string)
---@field SetCategory fun(name: string)
---@field SetCollapsed fun(id: string, collapsed: boolean)
---@field FolderOf fun(id: string): string?
---@field Select fun(id: string?)

---@class PQI_UI
---@field GuideLabel fun(guide: PQI_Guide): string?
---@field QuestTitle fun(id: number): string?
---@field ShowPicker fun()
---@field Picker PQI_Picker?

---@class PQI_L
---@field [string] string

---@class PQI_Polestar
---@field L PQI_L
---@field Compat PQI_Compat
---@field Guides PQI_Guides
---@field UI PQI_UI?
---@field Names PQI_Names?
---@field QuestDB PQI_QuestDB?
---@field Dungeons PQI_Dungeons?
---@field Theme PQI_Theme?
---@field Hooks PQI_Hooks?
---@field Widgets PQI_Widgets?
---@field Quoted fun(name: string): string
---@field NoteError fun(err: string?)
---@field IsLoggedIn fun(): boolean
---@field After fun(seconds: number, fn: fun())
---@field Hidden fun(): boolean
---@field GamepadUI fun(): boolean
---@field CreateFrameUnder fun(kind: FrameType, name: string?, parent: Frame?, template: string?): Frame
---@field On fun(message: string, fn: fun(...))
---@field OnLogin fun(fn: fun())
---@field OnInit fun(fn: fun())
---@field RegisterEvent fun(event: WowEvent, fn: fun(...))
---@field UnregisterEvent fun(event: WowEvent, fn: fun(...))

---@class PQI_Prose : FontString
---@field psGuideShown string?
---@field psGuideBase string?
---@field psGuideGrown number?
---@field psGuideFit boolean?

---@class PQI_GuideRow : Button
---@field hit PQI_Hit?
---@field plain string?
---@field tr number?
---@field tg number?
---@field tb number?
---@field Text FontString
---@field Why FontString
---@field Hover Texture

---@class PQI_Overlay : Frame
---@field rows PQI_GuideRow[]
---@field Header FontString

---@class PQI_TipOwner : Frame
---@field psGuideQuest number?
---@field psGuideAnchor string?
---@field psGuideBound boolean?
---@field psGuideOwned boolean?

---@class PQI_TextHost : PQI_TipOwner
---@field Text FontString?
---@field Icon Texture?
---@field isActive number?
---@field questID number?
---@field Resize fun(self: PQI_TextHost)?
---@field GetTextHeight fun(self: PQI_TextHost): number?

---@class PQI_QuestButton : PQI_TextHost

---@class PQI_Anchor
---@field point FramePoint
---@field rel Frame
---@field relPoint FramePoint
---@field x number
---@field y number

---@class PQI_RewardsFrame : Frame
---@field Header FontString?

---@class PQI_GreetingPanel : Frame
---@field titleButtonPool FramePool?

---@class PQI_TrackerQuest
---@field GetID fun(self: PQI_TrackerQuest): number?

---@class PQI_TrackerBlock : PQI_TipOwner
---@field HeaderText FontString?

---@class PQI_Tracker
---@field GetExistingBlock fun(self: PQI_Tracker, questID: number): PQI_TrackerBlock?

---@class PQI_GossipInfo
---@field questID number?

---@class PQI_QuestTemplate
---@field questLog boolean?

---@class PQI_TipData
---@field id number?
---@field hyperlink string?
---@field guid string?
