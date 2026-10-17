extends "res://scripts/gameplay/encounter_scaling.gd"

@export var contact_base: int = 4
@export var strength_threshold: int = 3
@export var health_threshold: int = 60
@export var creatures: Dictionary = {}

func decide(facts: Dictionary) -> Dictionary:
    var row: Dictionary=creatures.get(facts.creature,{})
    if row.is_empty():return {}
    var maximum: int=int(facts.maximum_hp)
    var alive: int=int(row.initial_alive)
    if int(facts.strength)>strength_threshold:alive+=1
    if maximum>=health_threshold:alive+=1
    if int(row.alive_cap)>0:alive=mini(alive,int(row.alive_cap))
    var damage: int=(contact_base+int(facts.strength)+int(facts.weapon_bonus))<<int(facts.moon_shift)
    # Retail LAB_021B/LAB_0177 use the low damage word and unsigned shifts.
    var column: int=(((damage&65535)+((maximum&65535)>>2))&65535)>>1
    column=(column-6)&65535
    if column&32768:column=0
    column=mini(column,15)>>1
    var count: int=int(facts.base_count)
    var reduced: int=count-int(row.cuts[column])
    return {"count":reduced if reduced>0 else count,"concurrent":alive}
